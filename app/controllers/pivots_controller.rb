# Pivots are created and edited on the map picker. A pivot's page lists its irrigation by season,
# with its weather zone's week ahead and a link to the zone (G.12).
class PivotsController < AuthenticatedController
  before_action :require_owner, only: :destroy
  allow_example :show, :weather

  def show
    pivot = Current.group.pivots.includes(:farm, :weather_cell, fields: [:soil_type, {plantings: :plant}]).find(params[:id])
    year = requested_year
    WeatherCell.keep_current([pivot.weather_cell_id])
    irrigations = PivotIrrigation.preload_areas(pivot.pivot_irrigations.where(date: Date.new(year).all_year).order(date: :desc))

    render inertia: "Pivots/Show", props: {
      pivot: PivotSerializer.new(pivot).to_h,
      farm: {id: pivot.farm.id, name: pivot.farm.name},
      year:,
      irrigations: PivotIrrigationSerializer.new(irrigations).to_h,
      # Fields' own irrigation that year, which replaces the system's (the form's per-field amounts)
      field_amounts: field_amounts(pivot, year),
      field_seasons: pivot.field_seasons,
      **WeatherZone.page_props(Current.group, pivot.weather_cell, forecast: year == Current.today.year)
    }
  end

  # The weather CSV moved to the pivot's zone (G.12); old links follow it
  def weather
    pivot = Current.group.pivots.find(params[:id])
    return head :not_found unless pivot.weather_cell

    redirect_to export_weather_zone_path(pivot.weather_cell.location, year: params[:year]), status: :moved_permanently
  end

  # ?copy_of= starts from another of the group's systems (Setup's Duplicate): its kind, size and
  # equipment, on its farm and in its group, but not its location, fields or plantings
  def new
    source = Current.group.pivots.find(params[:copy_of]) if params[:copy_of].present?
    pivot = source ? copy(source) : Pivot.new(farm: Current.group.farms.find_by(id: params[:farm_id]))
    render inertia: "Pivots/Form", props: form_props(pivot).merge(copy_of: source&.slice(:id, :name))
  end

  def create
    farm = Current.group.farms.find(pivot_params[:farm_id])
    pivot = farm.pivots.build(pivot_params.except(:pivot_group_id))
    # A duplicate joins its source's group, if it's still on that group's farm
    pivot.pivot_group = farm.pivot_groups.find_by(id: pivot_params[:pivot_group_id])
    if pivot.save
      redirect_to setup_path, notice: "Added #{pivot.name}. Add its fields with “Add field” when you're ready."
    else
      redirect_with_errors new_pivot_path(farm_id: pivot.farm_id, copy_of: params[:copy_of].presence), pivot
    end
  end

  def edit
    render inertia: "Pivots/Form", props: form_props(Current.group.pivots.find(params[:id]))
  end

  def update
    pivot = Current.group.pivots.find(params[:id])
    pivot.farm = Current.group.farms.find(pivot_params[:farm_id]) if pivot_params[:farm_id]
    if pivot.update(pivot_params.except(:farm_id))
      redirect_to setup_path, notice: "Saved #{pivot.name}"
    else
      redirect_with_errors edit_pivot_path(pivot), pivot
    end
  end

  def destroy
    pivot = Current.group.pivots.find(params[:id])
    pivot.destroy!
    redirect_to setup_path, notice: "Deleted #{pivot.name}"
  end

  private

  def pivot_params
    params.expect(pivot: [:farm_id, :name, :kind, :latitude, :longitude, :radius_ft, :arc_start_deg, :arc_end_deg,
      :length_ft, :travel_ft, :travel_bearing_deg, :equipment, :pump_capacity_gpm, :inches_at_100, :notes, :pivot_group_id])
  end

  COPIED = %w[farm_id pivot_group_id kind radius_ft arc_start_deg arc_end_deg length_ft travel_ft travel_bearing_deg
    equipment pump_capacity_gpm inches_at_100].freeze

  def copy(source)
    Pivot.new(source.attributes.slice(*COPIED).merge("name" => "#{source.name} copy"))
  end

  # The pivot, the farms it can belong to, the group's other pivots to show on the map, and the soil
  # types to name the soil survey's suggestion
  def form_props(pivot)
    {
      pivot: pivot.new_record? ? new_pivot_props(pivot) : PivotSerializer.new(pivot).to_h.except("fields"),
      # The group a duplicate joins, named in the form
      pivot_group: pivot.pivot_group&.slice(:id, :name, :farm_id),
      farms: Current.group.farms.order(:name).map { |farm| {id: farm.id, name: farm.name} },
      other_pivots: Current.group.pivots.where.not(id: pivot.id).map do |other|
        other.slice(:id, :name, *PivotSerializer::SHAPE)
      end,
      soil_types: ReferenceProps.soil_types
    }
  end

  # {date => {field_id => {irrigation_in, irrigation_pct}}} for the fields that are or were on the
  # system, in the year
  def field_amounts(pivot, year)
    field_ids = Field.where(pivot_id: pivot.id).or(Field.where(id: pivot.plantings.select(:field_id))).select(:id)
    FieldEntry.where(field_id: field_ids, date: Date.new(year).all_year).where.not(irrigation_in: nil)
      .group_by(&:date).transform_values do |entries|
        entries.to_h { |entry| [entry.field_id, entry.slice(:irrigation_in, :irrigation_pct)] }
      end
  end

  # A new system's starting values: its farm, or everything copied from a duplicated one
  def new_pivot_props(pivot)
    pivot.attributes.slice("name", *COPIED).compact
  end
end

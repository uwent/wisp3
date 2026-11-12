# Pivots are created and edited on the map picker. A pivot's page lists its irrigation by season,
# with its weather zone's week ahead and a link to the zone (G.12).
class PivotsController < AuthenticatedController
  before_action :require_owner, only: :destroy

  def show
    pivot = Current.group.pivots.includes(:farm, :weather_cell, fields: [:soil_type, {plantings: :plant}]).find(params[:id])
    year = params.fetch(:year, Date.current.year).to_i
    WeatherCell.keep_current([pivot.weather_cell_id])
    irrigations = pivot.pivot_irrigations.where(date: Date.new(year).all_year).order(date: :desc)

    render inertia: "Pivots/Show", props: {
      pivot: PivotSerializer.new(pivot).to_h,
      farm: {id: pivot.farm.id, name: pivot.farm.name},
      year:,
      irrigations: PivotIrrigationSerializer.new(irrigations).to_h,
      **WeatherZone.page_props(Current.group, pivot.weather_cell, forecast: year == Date.current.year)
    }
  end

  # The weather CSV moved to the pivot's zone (G.12); old links follow it
  def weather
    pivot = Current.group.pivots.find(params[:id])
    redirect_to export_weather_zone_path(pivot.weather_cell_id, year: params[:year]), status: :moved_permanently
  end

  def new
    farm = Current.group.farms.find_by(id: params[:farm_id])
    render inertia: "Pivots/Form", props: form_props(Pivot.new(farm:))
  end

  def create
    pivot = Current.group.farms.find(pivot_params[:farm_id]).pivots.build(pivot_params)
    if pivot.save
      redirect_to setup_path, notice: "Added #{pivot.name}. Add its fields with “Add field” when you're ready."
    else
      redirect_with_errors new_pivot_path(farm_id: pivot.farm_id), pivot
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
      :length_ft, :travel_ft, :travel_bearing_deg, :equipment, :pump_capacity_gpm, :notes])
  end

  # The pivot, the farms it can belong to, the group's other pivots to show on the map, and the soil
  # types to name the soil survey's suggestion
  def form_props(pivot)
    {
      pivot: pivot.new_record? ? pivot.attributes.slice("farm_id") : PivotSerializer.new(pivot).to_h.except("fields"),
      farms: Current.group.farms.order(:name).map { |farm| {id: farm.id, name: farm.name} },
      other_pivots: Current.group.pivots.where.not(id: pivot.id).map do |other|
        other.slice(:id, :name, *PivotSerializer::SHAPE)
      end,
      soil_types: SoilTypeSerializer.new(SoilType.order(:field_capacity, :perm_wilting_pt)).to_h
    }
  end
end

# Systems are created and edited on the map picker. A system's page lists its irrigation by season,
# with its weather zone's week ahead and a link to the zone.
class SystemsController < AuthenticatedController
  before_action :require_owner, only: :destroy
  allow_example :show, :weather

  def show
    system = Current.group.systems.includes(:farm, :weather_cell, fields: [:soil_type, {plantings: :plant}]).find(params[:id])
    year = requested_year
    WeatherCell.keep_current([system.weather_cell_id])

    render inertia: "Systems/Show", props: {
      system: IrrigationSystemSerializer.new(system).to_h,
      farm: {id: system.farm.id, name: system.farm.name},
      year:,
      # The year's irrigation by date, newest first: each field's amount (D15: stored per field)
      irrigations: system.irrigation_on(Date.new(year).all_year).reverse_each.map do |date, entries|
        {date:, fields: entries.to_h { |field, entry| [field.id, entry.irrigation_in] }}
      end,
      field_seasons: system.field_seasons,
      **WeatherZone.page_props(Current.group, system.weather_cell, forecast: year == Current.today.year)
    }
  end

  # The pump capacity or depth at 100% set in the irrigation calculator (IrrigationCalculatorDialog), back
  # to the page it was on
  def equipment
    system = Current.group.systems.find(params[:id])
    if system.update(params.expect(system: [:pump_capacity_gpm, :inches_at_100]))
      redirect_back_or_to system_path(system), notice: "Saved #{system.name}'s equipment"
    else
      redirect_back_or_to system_path(system), alert: "Couldn't save #{system.name}: #{system.errors.full_messages.to_sentence}"
    end
  end

  # The weather CSV moved to the system's zone; old links follow it
  def weather
    system = Current.group.systems.find(params[:id])
    return head :not_found unless system.weather_cell

    redirect_to export_weather_zone_path(system.weather_cell.location, year: params[:year]), status: :moved_permanently
  end

  # ?copy_of= starts from another of the group's systems (Setup's Duplicate): its kind, size and
  # equipment, on its farm and in its group, but not its location, fields or plantings
  def new
    source = Current.group.systems.find(params[:copy_of]) if params[:copy_of].present?
    system = source ? copy(source) : IrrigationSystem.new(farm: Current.group.farms.find_by(id: params[:farm_id]))
    render inertia: "Systems/Form", props: form_props(system).merge(copy_of: source&.slice(:id, :name))
  end

  def create
    farm = Current.group.farms.find(system_params[:farm_id])
    system = farm.systems.build(system_params.except(:irrigation_group_id))
    # A duplicate joins its source's group, if it's still on that group's farm
    system.irrigation_group = farm.irrigation_groups.find_by(id: system_params[:irrigation_group_id])
    if system.save
      redirect_to setup_path, notice: "Added #{system.name}. Add its fields with “Add field” when you're ready."
    else
      redirect_with_errors new_system_path(farm_id: system.farm_id, copy_of: params[:copy_of].presence), system
    end
  end

  def edit
    render inertia: "Systems/Form", props: form_props(Current.group.systems.find(params[:id]))
  end

  def update
    system = Current.group.systems.find(params[:id])
    system.farm = Current.group.farms.find(system_params[:farm_id]) if system_params[:farm_id]
    if system.update(system_params.except(:farm_id))
      redirect_to setup_path, notice: "Saved #{system.name}"
    else
      redirect_with_errors edit_system_path(system), system
    end
  end

  def destroy
    system = Current.group.systems.find(params[:id])
    system.destroy!
    redirect_to setup_path, notice: "Deleted #{system.name}"
  end

  private

  def system_params
    params.expect(system: [:farm_id, :name, :kind, :latitude, :longitude, :radius_ft, :arc_start_deg, :arc_end_deg,
      :length_ft, :travel_ft, :travel_bearing_deg, :equipment, :pump_capacity_gpm, :inches_at_100, :notes, :irrigation_group_id])
  end

  COPIED = %w[farm_id irrigation_group_id kind radius_ft arc_start_deg arc_end_deg length_ft travel_ft travel_bearing_deg
    equipment pump_capacity_gpm inches_at_100].freeze

  def copy(source)
    IrrigationSystem.new(source.attributes.slice(*COPIED).merge("name" => "#{source.name} copy"))
  end

  # The system, the farms it can belong to, the group's other systems to show on the map, and the soil
  # types to name the soil survey's suggestion
  def form_props(system)
    {
      system: system.new_record? ? new_system_props(system) : IrrigationSystemSerializer.new(system).to_h.except("fields"),
      # The group a duplicate joins, named in the form
      irrigation_group: system.irrigation_group&.slice(:id, :name, :farm_id),
      farms: Current.group.farms.order(:name).map { |farm| {id: farm.id, name: farm.name} },
      # The group's other systems, drawn for reference; the map opens on the new system's farm's,
      # their fields' outlines included (fields_extent: [[west, south], [east, north]], or nil)
      other_systems: Current.group.systems.where.not(id: system.id).includes(:fields).map do |other|
        other.slice(:id, :name, :farm_id, *IrrigationSystemSerializer::SHAPE).merge(fields_extent: fields_extent(other))
      end,
      soil_types: ReferenceProps.soil_types,
      # The operation's field outlines, drawn on the map, and leaving a kept outline file's shapes already saved off it
      field_outlines: Current.group.fields.where.not(boundary: nil).pluck(:name, :boundary)
        .map { |name, boundary| {name:, boundary:} }
    }
  end

  # Its fields' outlines' bounding box, [[west, south], [east, north]]; nil with none outlined
  def fields_extent(system)
    points = system.fields.flat_map { |field| FieldBoundary.ring(field.boundary) }
    return if points.empty?
    lngs, lats = points.map(&:first), points.map(&:last)
    [[lngs.min, lats.min], [lngs.max, lats.max]]
  end

  # A new system's starting values: its farm, or everything copied from a duplicated one
  def new_system_props(system)
    system.attributes.slice("name", *COPIED).compact
  end
end

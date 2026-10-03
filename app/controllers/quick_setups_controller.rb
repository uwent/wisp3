# The guided first-run setup: a farm, a pivot on the map, and its fields with this season's crops
# in one form (QuickSetup)
class QuickSetupsController < AuthenticatedController
  def new
    render inertia: "Setup/Start", props: {
      farms: Current.group.farms.order(:name).map { |farm| {id: farm.id, name: farm.name} },
      plants: PlantSerializer.new(Plant.order(:name)).to_h,
      soil_types: SoilTypeSerializer.new(SoilType.order(:field_capacity)).to_h,
      default_soil_type_id: SoilType.find_by(key: SoilType::DEFAULT_KEY)&.id,
      year: Date.current.year
    }
  end

  def create
    setup = QuickSetup.new(Current.group, setup_params)
    if setup.save && setup.pivot.fields.empty?
      redirect_to setup_path, notice: "Added #{setup.pivot.name}. Add its fields here with “Add field” when you're ready."
    elsif setup.errors.empty?
      redirect_to root_path, notice: "#{setup.pivot.name} is set up. Weather for it is on the way."
    else
      redirect_with_errors new_quick_setup_path, setup.errors
    end
  end

  private

  def setup_params
    params.expect(setup: [
      :farm_id,
      farm: [:name],
      pivot: [:name, :latitude, :longitude, :radius_ft, :pump_capacity_gpm],
      fields: [[:name, :area_acres, :soil_type_id, :plant_id, :emergence_date]]
    ])
  end
end

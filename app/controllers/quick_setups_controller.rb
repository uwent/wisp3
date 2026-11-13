# The guided first-run setup: a farm, an irrigation system on the map and its fields in one form
# (QuickSetup), each after the first optional. Its save goes to Setup, whose next steps (`started`)
# carry on from what was made: a system, fields, then each field's planting (PLAN.md G.6).
class QuickSetupsController < AuthenticatedController
  def new
    render inertia: "Setup/Start", props: {
      farms: Current.group.farms.order(:name).map { |farm| {id: farm.id, name: farm.name} },
      soil_types: SoilTypeSerializer.new(SoilType.order(:field_capacity, :perm_wilting_pt)).to_h,
      default_soil_type_id: SoilType.find_by(key: SoilType::DEFAULT_KEY)&.id
    }
  end

  def create
    setup = QuickSetup.new(Current.group, setup_params)
    return redirect_with_errors new_quick_setup_path, setup.errors unless setup.save

    if setup.pivot
      redirect_to setup_path(started_pivot: setup.pivot.id), notice: "#{setup.pivot.name} is set up. Weather for it is on the way."
    else
      redirect_to setup_path(started_farm: setup.farm.id), notice: "#{setup.farm.name} is set up."
    end
  end

  private

  def setup_params
    params.expect(setup: [
      :farm_id,
      farm: [:name],
      pivot: [:name, :kind, :latitude, :longitude, :radius_ft, :arc_start_deg, :arc_end_deg, :length_ft,
        :travel_ft, :travel_bearing_deg, :pump_capacity_gpm],
      fields: [[:name, :area_acres, :soil_type_id]]
    ])
  end
end

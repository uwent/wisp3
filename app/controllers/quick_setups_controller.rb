# The guided first-run setup: a farm, an irrigation system on the map and its fields in one form
# (QuickSetup), each after the first optional. Its save goes to Setup, whose next steps (`started`)
# carry on from what was made: a system, fields, then each field's planting (PLAN.md G.6). From
# November through December it asks which season the plantings are for, next year's by default
# (G.8), and Setup opens on it.
class QuickSetupsController < AuthenticatedController
  # The month from which quick setup asks for a season (Ben, 2026-11-17: November 1 on)
  NEXT_SEASON_FROM_MONTH = 11

  def new
    render inertia: "Setup/Start", props: {
      seasons:,
      farms: Current.group.farms.order(:name).map { |farm| {id: farm.id, name: farm.name} },
      soil_types: ReferenceProps.soil_types,
      default_soil_type_id: ReferenceProps.default_soil_type_id
    }
  end

  def create
    setup = QuickSetup.new(Current.group, setup_params)
    return redirect_with_errors new_quick_setup_path, setup.errors unless setup.save

    year = seasons&.find { |season| season.to_s == params[:season].to_s }
    if setup.pivot
      redirect_to setup_path(started_pivot: setup.pivot.id, year:), notice: "#{setup.pivot.name} is set up. Weather for it is on the way."
    else
      redirect_to setup_path(started_farm: setup.farm.id, year:), notice: "#{setup.farm.name} is set up."
    end
  end

  private

  # This season and next, late in the year; nil the rest of it (no question asked)
  def seasons
    today = Current.today
    [today.year, today.year + 1] if today.month >= NEXT_SEASON_FROM_MONTH
  end

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

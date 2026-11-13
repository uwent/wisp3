# Setup (PLAN.md §11): the group's farms, pivots, fields and plantings, shown for one season. The
# group's own settings (name, rainfall) are on its page (GroupsController).
class SetupController < AuthenticatedController
  def show
    year = params.fetch(:year, Date.current.year).to_i
    farms = Current.group.farms.order(:name).includes(:pivot_groups, pivots: {fields: [:soil_type, {plantings: :plant}]})
    years = Current.group.plantings.distinct.pluck(Arel.sql("extract(year from season_start)::int"))

    render inertia: "Setup/Show", props: {
      year:,
      years: (years + [Date.current.year, year]).uniq.sort,
      farms: FarmSerializer.new(farms).to_h,
      plants: PlantSerializer.new(Plant.order(:name)).to_h,
      soil_types: SoilTypeSerializer.new(SoilType.order(:field_capacity, :perm_wilting_pt)).to_h,
      generic_curves: GenericCurveSerializer.all,
      started:
    }
  end

  private

  # What quick setup just made, for the next steps box (PLAN.md G.6): a system, or a farm saved alone
  def started
    if (pivot = Current.group.pivots.find_by(id: params[:started_pivot]))
      {farm_id: pivot.farm_id, pivot_id: pivot.id}
    elsif (farm = Current.group.farms.find_by(id: params[:started_farm]))
      {farm_id: farm.id, pivot_id: nil}
    end
  end
end

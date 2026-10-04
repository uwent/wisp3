# Setup (PLAN.md §11): the group's farms, pivots, fields and plantings, shown for one season. The
# group's own settings (name, rainfall) are on its page (GroupsController).
class SetupController < AuthenticatedController
  def show
    year = params.fetch(:year, Date.current.year).to_i
    farms = Current.group.farms.order(:name).includes(pivots: {fields: [:soil_type, {plantings: :plant}]})
    years = Current.group.plantings.distinct.pluck(Arel.sql("extract(year from season_start)::int"))

    render inertia: "Setup/Show", props: {
      year:,
      years: (years + [Date.current.year, year]).uniq.sort,
      farms: FarmSerializer.new(farms).to_h,
      plants: PlantSerializer.new(Plant.order(:name)).to_h,
      soil_types: SoilTypeSerializer.new(SoilType.order(:field_capacity)).to_h
    }
  end
end

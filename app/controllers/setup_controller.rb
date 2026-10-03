# Setup (PLAN.md §11): the group's farms, pivots, fields and plantings, shown for one season, and
# the group's own settings (name, modeled or manual rainfall).
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

  def update
    if Current.group.update(params.expect(group: [:name, :use_model_precip]))
      redirect_to setup_path, notice: "Saved"
    else
      redirect_with_errors setup_path, Current.group
    end
  end
end

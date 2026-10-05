# Every field's water status today (PLAN.md §11), by farm and pivot: one card per field with this
# season's planting. Pivots without fields are listed too, so the hierarchy matches setup.
class DashboardController < AuthenticatedController
  def show
    today = Date.current
    farms = Current.group.farms.order(:name).includes(pivots: [:weather_cell,
      {fields: [:soil_type, {plantings: [:plant, :canopy_observations]}]}]).to_a
    pivots = farms.flat_map { |farm| farm.pivots.sort_by(&:name) }
    fields = pivots.flat_map(&:fields)
    WeatherCell.keep_current(pivots.map(&:weather_cell_id).uniq)
    statuses = FieldStatuses.for(fields, today:)

    card = lambda do |field|
      status = statuses[field.id]
      {id: field.id, name: field.name, summary: status && PlantingSummarySerializer.new(status).to_h}
    end

    render inertia: "Dashboard/Show", props: {
      today:,
      farms: farms.map do |farm|
        {id: farm.id, name: farm.name, pivots: farm.pivots.sort_by(&:name).map do |pivot|
          {id: pivot.id, name: pivot.name, fields: pivot.fields.map { |field| card.call(field) }}
        end}
      end
    }
  end
end

# Every field's water status today (PLAN.md §11), by farm and pivot: one card per field with this
# season's planting. Pivots without fields are listed too, so the hierarchy matches setup.
class DashboardController < AuthenticatedController
  def show
    today = Date.current
    farms = Current.group.farms.order(:name).includes(pivots: [:weather_cell,
      {fields: [:soil_type, {plantings: [:plant, :canopy_observations]}]}]).to_a
    pivots = farms.flat_map { |farm| farm.pivots.sort_by(&:name) }
    fields = pivots.flat_map(&:fields)
    plantings = fields.to_h do |field|
      [field.id, field.planting_on(today) ||
        field.plantings.select { |p| p.season_year == today.year }.min_by { |p| (p.season_start - today).abs }]
    end

    # Every card's entries and weather in a few queries, not several per field
    starts = plantings.values.compact.map(&:season_start)
    dates = starts.any? ? starts.min..[today, plantings.values.compact.map(&:end_date).max].min : today..today
    records = DailyInputs.preload(fields, dates)
    cell_ids = pivots.map(&:weather_cell_id).uniq
    WeatherCell.keep_current(cell_ids)
    weather = WeatherDay.balance_inputs_by_cell(cell_ids, dates)

    card = lambda do |field, pivot|
      planting = plantings[field.id]
      status = planting && PlantingStatus.new(planting, today:, records: records[field.id],
        weather: weather.fetch(pivot.weather_cell_id, {}))
      {id: field.id, name: field.name, summary: status && PlantingSummarySerializer.new(status).to_h}
    end

    render inertia: "Dashboard/Show", props: {
      today:,
      farms: farms.map do |farm|
        {id: farm.id, name: farm.name, pivots: farm.pivots.sort_by(&:name).map do |pivot|
          {id: pivot.id, name: pivot.name, fields: pivot.fields.map { |field| card.call(field, pivot) }}
        end}
      end
    }
  end
end

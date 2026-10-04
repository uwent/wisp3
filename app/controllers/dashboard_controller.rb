# Every field's water status today (PLAN.md §11): one card per field with this season's planting
class DashboardController < AuthenticatedController
  def show
    today = Date.current
    fields = Current.group.fields.includes(:soil_type, pivot: [{farm: :group}, :weather_cell],
      plantings: [:plant, :canopy_observations]).sort_by { |field| [field.pivot.farm.name, field.pivot.name, field.name] }
    plantings = fields.to_h do |field|
      [field.id, field.planting_on(today) ||
        field.plantings.select { |p| p.season_year == today.year }.min_by { |p| (p.season_start - today).abs }]
    end

    # Every card's entries and weather in a few queries, not several per field
    starts = plantings.values.compact.map(&:season_start)
    dates = starts.any? ? starts.min..[today, plantings.values.compact.map(&:end_date).max].min : today..today
    records = DailyInputs.preload(fields, dates)
    weather = WeatherDay.balance_inputs_by_cell(fields.map { |field| field.pivot.weather_cell_id }.uniq, dates)

    cards = fields.map do |field|
      planting = plantings[field.id]
      status = planting && PlantingStatus.new(planting, today:, records: records[field.id],
        weather: weather.fetch(field.pivot.weather_cell_id, {}))
      {
        field: {id: field.id, name: field.name},
        pivot: {id: field.pivot.id, name: field.pivot.name},
        farm: {id: field.pivot.farm.id, name: field.pivot.farm.name},
        summary: status && PlantingSummarySerializer.new(status).to_h
      }
    end

    render inertia: "Dashboard/Show", props: {
      today:,
      cards:,
      farm_count: Current.group.farms.count
    }
  end
end

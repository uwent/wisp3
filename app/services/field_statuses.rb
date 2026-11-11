# The status of many fields at once (the dashboard, the daily digest): each field's planting for
# today (or the nearest one this year), with entries, weather and ensembles for every field loaded
# in a few queries, not several per field, through the projection's days. Fields need their pivot
# and plantings (with plant and canopy observations) and soil type loaded.
class FieldStatuses
  # {field_id => PlantingStatus, or nil for a field with no planting this year}
  def self.for(fields, today: Date.current)
    plantings = fields.to_h do |field|
      [field.id, field.planting_on(today) ||
        field.plantings.select { |p| p.season_year == today.year }.min_by { |p| (p.season_start - today).abs }]
    end

    current = plantings.values.compact
    last = [today + PlantingStatus::HORIZON, current.map(&:end_date).max].compact.min
    dates = current.any? ? current.map(&:season_start).min..last : today..today
    records = DailyInputs.preload(fields, dates)
    # Each planting's weather cell: its pivot's, or where the pivot was in an ended season (G.9)
    cell_ids = current.map(&:weather_cell_id).uniq
    weather = WeatherDay.balance_inputs_by_cell(cell_ids, dates)
    ensembles = WeatherForecast.ensemble.latest_by_cell(cell_ids).transform_values(&:members)

    fields.to_h do |field|
      planting = plantings[field.id]
      cell_id = planting&.weather_cell_id
      [field.id, planting && PlantingStatus.new(planting, today:, records: records[field.id],
        weather: weather.fetch(cell_id, {}), ensemble: ensembles.fetch(cell_id, []))]
    end
  end
end

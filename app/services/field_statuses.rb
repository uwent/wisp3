# The status of many fields at once (the dashboard, the map, the daily digest): each field's
# plantings in season today (several on a field of plots, PLAN.md Phase 8 G.11), or with none, the
# nearest one this year, with entries, weather and ensembles for every field loaded in a few
# queries, not several per field, through the projection's days. Fields need their pivot and
# plantings (with plant and canopy observations) and soil type loaded.
class FieldStatuses
  RANK = {irrigate: 0, caution: 1, ok: 2, full: 3}.freeze

  # {field_id => [PlantingStatus, …]}, whole-field planting first, then by season start; empty for a
  # field with no planting this year
  def self.for(fields, today: Date.current)
    plantings = fields.to_h { |field| [field.id, plantings_for(field, today)] }

    current = plantings.values.flatten
    last = [today + PlantingStatus::HORIZON, current.map(&:end_date).max].compact.min
    dates = current.any? ? current.map(&:season_start).min..last : today..today
    records = DailyInputs.preload(fields, dates)
    # Each planting's weather cell: its pivot's, or where the pivot was in an ended season (G.9)
    cell_ids = current.map(&:weather_cell_id).uniq
    weather = WeatherDay.balance_inputs_by_cell(cell_ids, dates)
    ensembles = WeatherForecast.ensemble.latest_by_cell(cell_ids).transform_values(&:members)

    fields.to_h do |field|
      [field.id, plantings[field.id].map do |planting|
        cell_id = planting.weather_cell_id
        PlantingStatus.new(planting, today:, records: records[field.id], weather: weather.fetch(cell_id, {}),
          ensemble: ensembles.fetch(cell_id, []))
      end]
    end
  end

  # The plantings in season today; with none, the one this year nearest today and those it shares
  # days with (so a field of plots shows them all out of season, and a succession just the one)
  def self.plantings_for(field, today)
    on = field.plantings_on(today)
    if on.empty?
      year = field.plantings.select { |p| p.season_year == today.year }
      nearest = year.min_by { |p| (p.season_start - today).abs }
      on = nearest ? year.select { |p| p.overlaps?(nearest) } : []
    end
    on.sort_by { |planting| [planting.partial? ? 1 : 0, planting.season_start, planting.id] }
  end

  # How urgent a planting's status is, most urgent lowest: in season by status (irrigate, caution,
  # ok, full), soonest crossing first, then in season without a status, upcoming and ended. The
  # dashboard's urgency (lib/overview.ts) reads the same.
  def self.urgency(status)
    return [RANK.size + 3, 0] unless status
    case status.phase
    when :upcoming then [RANK.size + 1, 0]
    when :ended then [RANK.size + 2, 0]
    else
      rank = (status.status && !status.weather_pending?) ? RANK.fetch(status.status) : RANK.size
      [rank, status.crossing&.days || PlantingStatus::HORIZON + 1]
    end
  end

  # A field's most urgent planting, which places it among the others
  def self.most_urgent(statuses) = statuses.min_by { |status| urgency(status) }
end

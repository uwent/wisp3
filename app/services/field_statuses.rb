# The status of many fields at once (the dashboard, the map, the daily digest): each field's
# plantings in season today (several on a field of plots), or with none, the
# nearest one this year (or the next to start), with entries, weather and ensembles for every field loaded in a few
# queries, not several per field, through the projection's days. Fields need their system and
# plantings (with plant and canopy observations) and soil type loaded.
class FieldStatuses
  # Irrigated crops by what they need, then rainfed ones by their stress (nothing to do for them)
  RANK = {irrigate: 0, caution: 1, needs_canopy: 2, ok: 3, full: 4, stressed: 5, stress_coming: 6, no_stress: 7}.freeze

  # {field_id => [PlantingStatus, …]}, whole-field planting first, then by season start; empty for a
  # field with no planting this year or ahead. Another year (the map's season) gives every planting
  # that started in it, as they ended (or stand, or will start). as_of: the example farm's day
  # (Current.as_of), today for every planting (status).
  def self.for(fields, today: Current.today, year: today.year, as_of: Current.as_of)
    plantings = fields.to_h { |field| [field.id, plantings_for(field, today, year)] }

    current = plantings.values.flatten
    # Through the projection's days, or as of the example farm's day, the days that followed it
    last = [[today, as_of].compact.max + PlantingStatus::HORIZON, current.map(&:end_date).max].compact.min
    dates = current.any? ? current.map(&:season_start).min..last : today..today
    records = DailyInputs.preload(fields, dates)
    # Each planting's weather cell: its system's, or where the system was in an ended season
    cell_ids = current.map(&:weather_cell_id).uniq
    weather = WeatherDay.balance_inputs_by_cell(cell_ids, dates)
    ensembles = as_of ? {} : WeatherForecast.ensemble.latest_by_cell(cell_ids).transform_values(&:members)
    # Temperatures for canopy curves in degree days (C23), over each curve's own dates
    temperatures = CellTemperatures.for_plantings(current)

    fields.to_h do |field|
      [field.id, plantings[field.id].map do |planting|
        cell_id = planting.weather_cell_id
        status(planting, today:, as_of:, records: records[field.id], weather: weather.fetch(cell_id, {}),
          ensemble: ensembles.fetch(cell_id, []), temperatures: temperatures[cell_id])
      end]
    end
  end

  # A planting's status today; as of the example farm's day (as_of) through time travel's view of it
  # (PlantingStatus as_of: what followed in place of a forecast) when its season covers the day, as
  # it then stood (upcoming or ended) otherwise. records: the field's, covering the planting's season
  # through as_of's days that followed (PlantingStatus) when time travelling
  def self.status(planting, today:, as_of: nil, records: nil, weather: nil, ensemble: :load, temperatures: nil)
    if as_of && planting.season_range.cover?(as_of)
      PlantingStatus.new(planting, as_of:, records:, weather:, temperatures:)
    else
      PlantingStatus.new(planting, today:, records:, weather:, ensemble: as_of ? [] : ensemble, temperatures:)
    end
  end

  # The plantings in season today; with none, the one this year nearest today and those it shares
  # days with (so a field of plots shows them all out of season, and a succession just the one);
  # with none this year, the next to start (next season's, set up over the winter); in another
  # year, all of that year's
  def self.plantings_for(field, today, year = today.year)
    return field.plantings.select { |p| p.season_year == year }.sort_by(&:order_key) unless year == today.year

    on = field.plantings_on(today)
    if on.empty?
      near = field.plantings.select { |p| p.season_year == today.year }.presence ||
        field.plantings.select { |p| p.season_start > today }
      nearest = near.min_by { |p| (p.season_start - today).abs }
      on = nearest ? near.select { |p| p.overlaps?(nearest) } : []
    end
    on.sort_by(&:order_key)
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

# A weather cell's daily highs and lows for canopy curves in thermal time (ThermalTime, PLAN.md §9
# C23): stored days (WeatherDay) for the past, the latest forecast for today and the days ahead,
# and the cell's normals (WeatherNormal) for every other day, after the forecast or missing in the
# past. Without normals the cell has no thermal time, and curves run by calendar days.
class CellTemperatures
  # observed: {date => [tmax_f, tmin_f]}, stored then forecast; normals: {day_of_year => [tmax_f, tmin_f]}
  def initialize(observed, normals)
    @observed, @normals = observed, normals || {}
    @thermal = {}
  end

  # {cell_id => CellTemperatures} over a range of dates, in three queries (stored days, the latest
  # forecasts, normals), for pages running many plantings (FieldStatuses)
  def self.by_cell(cell_ids, dates)
    cell_ids = cell_ids.compact.uniq
    return {} if cell_ids.empty?
    observed = WeatherDay.where(weather_cell_id: cell_ids, date: dates).where.not(tmax_f: nil).where.not(tmin_f: nil)
      .pluck(:weather_cell_id, :date, :tmax_f, :tmin_f).group_by(&:first)
      .transform_values { |rows| rows.to_h { |_, date, tmax, tmin| [date, [tmax, tmin]] } }
    WeatherForecast.deterministic.latest_by_cell(cell_ids).each do |cell_id, forecast|
      days = observed[cell_id] ||= {}
      forecast.days.each do |date, values|
        next if days.key?(date) || !dates.cover?(date) || values["tmax_f"].nil? || values["tmin_f"].nil?
        days[date] = [values["tmax_f"], values["tmin_f"]]
      end
    end
    normals = WeatherNormal.by_cell(cell_ids)
    cell_ids.to_h { |id| [id, new(observed.fetch(id, {}), normals[id])] }
  end

  # {cell_id => CellTemperatures} for the cells of plantings whose canopy curve can run in degree
  # days, over the dates each one's curve looks at (ThermalTime.dates_for), in three queries
  def self.for_plantings(plantings)
    thermal = plantings.select { |planting| planting.weather_cell_id && planting.thermal_curve? }
    return {} if thermal.empty?
    ranges = thermal.map { |planting| ThermalTime.dates_for(planting) }
    by_cell(thermal.map(&:weather_cell_id), ranges.map(&:min).min..ranges.map(&:max).max)
  end

  # One cell's, over the dates a planting's curve looks at (ThermalTime.dates_for)
  def self.for(cell_id, dates) = cell_id ? by_cell([cell_id], dates).fetch(cell_id) : new({}, nil)

  def normals? = @normals.any?

  # [tmax_f, tmin_f] on date: observed, else the normal (nil without normals)
  def on(date) = @observed[date] || @normals[WeatherNormal.day_of_year(date)]

  # The ThermalTime for a crop's base and upper temperatures, or nil without normals
  def thermal_time(base_c:, upper_c:)
    return unless normals?
    @thermal[[base_c, upper_c]] ||= ThermalTime.new(self, base_c:, upper_c:)
  end
end

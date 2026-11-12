# The week ahead for a cell in brief (the forecast strip, G.12), from what's already stored: the
# latest deterministic forecast (corrected as stored days are) for each day's sky, temperatures,
# precipitation, ET and wind, and the latest ensemble for the chance of precipitation (the share of
# its members with at least WET_IN that day). Values as stored (inches, °F, mph); missing is nil.
class ForecastDays
  DAYS = 7
  WET_IN = 0.01

  Day = Data.define(:date, :weather_code, :tmax_f, :tmin_f, :precip_in, :snowfall_in, :precip_chance, :et0_in,
    :cloud_cover_pct, :wind_speed_max_mph, :wind_gust_max_mph)

  COLUMNS = %w[weather_code tmax_f tmin_f precip_in snowfall_in et0_in cloud_cover_pct wind_speed_max_mph wind_gust_max_mph].freeze

  # {cell_id => [Day]} from today, at most DAYS, in two queries; [] without a forecast
  def self.by_cell(cell_ids, today: Date.current)
    cell_ids = cell_ids.compact.uniq
    forecasts = WeatherForecast.deterministic.latest_by_cell(cell_ids)
    ensembles = WeatherForecast.ensemble.latest_by_cell(cell_ids)
    cell_ids.to_h do |cell_id|
      [cell_id, days(forecasts[cell_id], ensembles[cell_id], today)]
    end
  end

  def self.for(cell, today: Date.current) = cell ? by_cell([cell.id], today:).fetch(cell.id) : []

  def self.days(forecast, ensemble, today)
    return [] unless forecast

    chances = chances(ensemble)
    forecast.days.select { |date, _| date >= today }.sort.first(DAYS).map do |date, values|
      Day.new(date:, precip_chance: chances[date], **COLUMNS.to_h { |column| [column.to_sym, rounded(values[column])] })
    end
  end

  # {date => percent of members with at least WET_IN}
  def self.chances(ensemble)
    return {} unless ensemble

    ensemble.members.flat_map(&:to_a).group_by(&:first).transform_values do |pairs|
      amounts = pairs.filter_map { |_, values| values[:precip] }
      amounts.any? ? (100.0 * amounts.count { |inches| inches >= WET_IN } / amounts.size).round : nil
    end
  end

  def self.rounded(value) = value.is_a?(Float) ? value.round(3) : value

  private_class_method :days, :chances, :rounded
end

# The week ahead for a cell in brief (the forecast strip, G.12), from what's already stored: the
# latest deterministic forecast (corrected as stored days are) for each day's sky, temperatures,
# precipitation, ET and wind, and the latest ensemble for the chance of rain (the share of its
# members with at least WET_IN that day: model agreement at the zone's grid point, not the NWS's
# PoP; docs/plans/phase-9.md §9). Values as stored (inches, °F, mph); missing is nil.
#
# For the example farm (Current.as_of, PLAN.md G.8) the week is the stored days that followed its
# day, with no sky (stored days have no weather code) or chance of precipitation.
class ForecastDays
  DAYS = 7
  # Rain that counts: enough to wet the soil surface (SoilEvaporation), and leaving out the drizzle
  # a coarse ensemble spreads over its whole cell on showery days
  WET_IN = 0.1

  Day = Data.define(:date, :weather_code, :tmax_f, :tmin_f, :precip_in, :snowfall_in, :precip_chance, :et0_in,
    :cloud_cover_pct, :wind_speed_max_mph, :wind_gust_max_mph)

  COLUMNS = %w[weather_code tmax_f tmin_f precip_in snowfall_in et0_in cloud_cover_pct wind_speed_max_mph wind_gust_max_mph].freeze

  # {cell_id => [Day]} from today, at most DAYS, in two queries; [] without a forecast
  def self.by_cell(cell_ids, today: Current.today, observed: Current.as_of.present?)
    cell_ids = cell_ids.compact.uniq
    return observed_by_cell(cell_ids, today) if observed

    forecasts = WeatherForecast.deterministic.latest_by_cell(cell_ids)
    ensembles = WeatherForecast.ensemble.latest_by_cell(cell_ids)
    cell_ids.to_h do |cell_id|
      [cell_id, days(forecasts[cell_id], ensembles[cell_id], today)]
    end
  end

  def self.for(cell, today: Current.today) = cell ? by_cell([cell.id], today:).fetch(cell.id) : []

  # The stored days from today, as the week ahead
  def self.observed_by_cell(cell_ids, today)
    columns = COLUMNS - ["weather_code"]
    rows = WeatherDay.where(weather_cell_id: cell_ids, date: today...(today + DAYS)).order(:date)
      .pluck(:weather_cell_id, :date, *columns).group_by(&:first)
    cell_ids.to_h do |cell_id|
      [cell_id, (rows[cell_id] || []).map do |_, date, *values|
        Day.new(date:, weather_code: nil, precip_chance: nil, **columns.zip(values).to_h { |column, value| [column.to_sym, rounded(value)] })
      end]
    end
  end

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

  private_class_method :observed_by_cell, :days, :chances, :rounded
end

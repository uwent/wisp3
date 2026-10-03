# Weather for a field's page: the cell's stored days over a date range, then the latest forecast for
# the days after them, with growing degree days since emergence (0 before it).
class WeatherPanel
  COLUMNS = %i[
    et0_in precip_in tmax_f tmin_f tmean_f dew_point_f rh_mean_pct rh_min_pct vpd_max_kpa wind_speed_mph
    wind_gust_max_mph wind_direction_deg cloud_cover_pct soil_temp_0_7cm_f soil_temp_7_28cm_f soil_temp_28_100cm_f
    soil_temp_100_255cm_f soil_moisture_0_7cm soil_moisture_7_28cm soil_moisture_28_100cm soil_moisture_100_255cm
  ].freeze

  Day = Data.define(:date, :forecast, :gdd, :gdd_since_emergence, *COLUMNS)

  def initialize(cell, dates, emergence_date:)
    @cell, @dates, @emergence_date = cell, dates, emergence_date
  end

  def days
    return [] unless @cell
    stored = @cell.weather_days.where(date: @dates).order(:date).pluck(:date, *COLUMNS)
      .to_h { |date, *values| [date, COLUMNS.zip(values.map { |value| value&.round(3) }).to_h] }
    last_stored = stored.keys.max
    forecast = (@cell.latest_forecast&.days || {})
      .select { |date, _| @dates.cover?(date) && (last_stored.nil? || date > last_stored) }
      .transform_values { |values| COLUMNS.to_h { |column| [column, values[column.to_s]&.round(3)] } }

    gdd_total = 0.0
    stored.merge(forecast).sort.map do |date, values|
      gdd = Weather::DegreeDays.daily(values[:tmax_f], values[:tmin_f])
      gdd_total += gdd.to_f if date >= @emergence_date
      Day.new(date:, forecast: forecast.key?(date), gdd: gdd&.round(1),
        gdd_since_emergence: (date >= @emergence_date) ? gdd_total.round(1) : 0.0, **values)
    end
  end
end

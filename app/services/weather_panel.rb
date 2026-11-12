# Weather for a field's page: the cell's stored days over a date range, then the latest forecast for
# the days after them, with growing degree days since emergence (0 before it), and the corrections
# each day went through (PLAN.md §8.5). RAW_COLUMNS, Open-Meteo's values before the corrections, are
# for the CSV (WeatherCsv), not the page.
class WeatherPanel
  COLUMNS = %i[
    et0_in shortwave_mj precip_in rain_in snowfall_in snow_depth_in tmax_f tmin_f tmean_f dew_point_f rh_mean_pct rh_min_pct vpd_max_kpa wind_speed_mph
    wind_gust_max_mph wind_direction_deg cloud_cover_pct soil_temp_0_7cm_f soil_temp_7_28cm_f soil_temp_28_100cm_f
    soil_temp_100_255cm_f soil_moisture_0_7cm soil_moisture_7_28cm soil_moisture_28_100cm soil_moisture_100_255cm
  ].freeze
  RAW_COLUMNS = %i[et0_openmeteo_in shortwave_raw_mj dew_point_raw_f rh_mean_raw_pct rh_min_raw_pct].freeze
  ALL_COLUMNS = COLUMNS + RAW_COLUMNS

  Day = Data.define(:date, :forecast, :gdd, :gdd_since_emergence, :corrections, *ALL_COLUMNS)

  def initialize(cell, dates, emergence_date:)
    @cell, @dates, @emergence_date = cell, dates, emergence_date
  end

  def days
    return [] unless @cell
    stored = @cell.weather_days.where(date: @dates).order(:date).pluck(:date, :corrections, *ALL_COLUMNS)
      .to_h { |date, corrections, *values| [date, ALL_COLUMNS.zip(values.map { |value| value&.round(3) }).to_h.merge(corrections:)] }
    last_stored = stored.keys.max
    forecast = (@cell.latest_forecast&.days || {})
      .select { |date, _| @dates.cover?(date) && (last_stored.nil? || date > last_stored) }
      .transform_values { |values| ALL_COLUMNS.to_h { |column| [column, values[column.to_s]&.round(3)] }.merge(corrections: values["corrections"] || []) }

    gdd_total = 0.0
    # A day with no values (the forecast's last, partial day) is left out, so no running total
    # (degree days) carries on past the others
    stored.merge(forecast).reject { |_, values| ALL_COLUMNS.all? { |column| values[column].nil? } }.sort.map do |date, values|
      gdd = Weather::DegreeDays.daily(values[:tmax_f], values[:tmin_f])
      gdd_total += gdd.to_f if date >= @emergence_date
      Day.new(date:, forecast: forecast.key?(date), gdd: gdd&.round(1),
        gdd_since_emergence: (date >= @emergence_date) ? gdd_total.round(1) : nil, **values)
    end
  end
end

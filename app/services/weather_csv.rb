# A pivot's weather as CSV: frontmatter (CsvExport), then every variable WISP stores for its weather
# grid cell, one row per day (WeatherPanel's days: the stored ones, then the latest forecast's,
# marked), with growing degree days. Values as stored.
class WeatherCsv
  include CsvExport

  # A label for each of WeatherPanel::COLUMNS, with its unit (soil depths as on the weather charts)
  COLUMNS = {
    et0_in: "Reference ET (in)", precip_in: "Precipitation (in)", rain_in: "Rain (in)", snowfall_in: "Snowfall (in)",
    snow_depth_in: "Snow depth (in)", tmax_f: "High temperature (°F)", tmin_f: "Low temperature (°F)",
    tmean_f: "Mean temperature (°F)", dew_point_f: "Dew point (°F)", rh_mean_pct: "Relative humidity, mean (%)",
    rh_min_pct: "Relative humidity, low (%)", vpd_max_kpa: "Vapor pressure deficit, high (kPa)",
    wind_speed_mph: "Wind speed, mean (mph)", wind_gust_max_mph: "Wind gust, highest (mph)",
    wind_direction_deg: "Wind direction (degrees)", cloud_cover_pct: "Cloud cover (%)",
    soil_temp_0_7cm_f: "Soil temperature, 0–3 in (°F)", soil_temp_7_28cm_f: "Soil temperature, 3–11 in (°F)",
    soil_temp_28_100cm_f: "Soil temperature, 11–39 in (°F)", soil_temp_100_255cm_f: "Soil temperature, 39–100 in (°F)",
    soil_moisture_0_7cm: "Soil moisture, 0–3 in (m³/m³)", soil_moisture_7_28cm: "Soil moisture, 3–11 in (m³/m³)",
    soil_moisture_28_100cm: "Soil moisture, 11–39 in (m³/m³)", soil_moisture_100_255cm: "Soil moisture, 39–100 in (m³/m³)"
  }.freeze

  UNITS = "inches, °F, mph, kPa and percent, and soil moisture as a fraction of the soil's volume (m³/m³), as stored"

  def initialize(pivot, year, days, exported_by: nil, about_url: nil)
    @pivot, @year, @days, @exported_by, @about_url = pivot, year, days, exported_by, about_url
  end

  def to_csv
    cell = @pivot.weather_cell
    generate do |csv|
      frontmatter(csv, "WISP weather, #{@pivot.name}, #{@year}", {
        "Operation" => @pivot.farm.group.name,
        "Pivot" => "#{@pivot.farm.name} / #{@pivot.name}",
        "Location" => cell && "the weather grid cell centered at #{cell.latitude}, #{cell.longitude}" \
          "#{", #{cell.elevation_m.round} m above sea level" if cell.elevation_m}",
        "Days" => days_line,
        "Growing degree days" => @days.any? ? "the 50/86 °F method, added up from #{@days.first.date}" : nil
      }, exported_by: @exported_by, about_url: @about_url, units: UNITS)
      csv << ["Date", "Forecast", *COLUMNS.values, "GDD (50/86 °F)", "GDD since the first day (50/86 °F)"]
      @days.each do |day|
        csv << [day.date, day.forecast ? "yes" : "no", *COLUMNS.keys.map { |column| num(day.public_send(column)) },
          num(day.gdd), num(day.gdd_since_emergence)]
      end
    end
  end

  private

  def days_line
    return "none yet" if @days.empty?
    forecast = @days.count(&:forecast)
    line = "#{@days.first.date} to #{@days.last.date}, one row each"
    return line if forecast.zero?
    "#{line}; #{(forecast == 1) ? "the last is" : "the last #{forecast} are"} from the latest forecast"
  end
end

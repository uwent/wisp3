# WISP 3's own weather at the Central Sands flux towers (docs/et-validation/04-weather.md): for each
# tower season, Open-Meteo's historical forecasts at the tower's weather cell run through WISP's
# hourly merge, corrections and FAO-56 ET0 (Weather::Comparison, as `weather:compare` does), and
# AgWeather's gridded ET at the tower (legacy WISP's input; classic and `method=adjusted`). Before
# 2025 Open-Meteo's historical forecasts have no NBM, so WISP's chain runs on best_match alone.
#
#   bin/rails runner docs/et-validation/scripts/weather_at_towers.rb [OUT]
#
# Needs the network (Open-Meteo, AgWeather). OUT defaults to tmp/ameriflux/wisp_weather.csv. Values
# in mm (ET) and as WISP stores them otherwise (wind mph at 10 m, RH %).
require "csv"

TOWERS = {
  "US-CS1" => [44.1031, -89.5379, 2018], "US-CS3" => [44.1394, -89.5727, 2019],
  "US-CS4" => [44.1597, -89.5475, 2020], "US-CS5" => [44.1095, -89.5377, 2021],
  "US-CS6" => [44.4297, -89.5440, 2022], "US-CS8" => [44.4338, -89.5364, 2023]
}.freeze
MM = 25.4
out = ARGV[0] || "tmp/ameriflux/wisp_weather.csv"

def agweather_et(lat, lng, dates, adjusted:)
  params = {lat: lat.round(1), long: lng.round(1), start_date: dates.first, end_date: dates.last, units: "in"}
  params[:method] = "adjusted" if adjusted # the point endpoint's name (the grid's is et_method)
  uri = URI("#{Weather::Comparison::AGWEATHER}/evapotranspirations?" + URI.encode_www_form(params))
  JSON.parse(Net::HTTP.get(uri)).fetch("data").to_h { |day| [Date.parse(day["date"]), day["value"]] }
rescue => e
  warn "AgWeather #{adjusted ? "adjusted" : "classic"} failed: #{e.message}"
  {}
end

CSV.open(out, "w") do |csv|
  csv << %w[site date et0_wisp_mm et0_openmeteo_mm et0_wisp_2026_mm wind_mph rh_min_pct precip_mm agweather_classic_mm agweather_adjusted_mm]
  TOWERS.each do |site, (lat, lng, year)|
    warn "#{site} #{year}"
    comparison = Weather::Comparison.new(points: [[site, lat, lng]], years: [year])
    dates = comparison.season(year)
    series = begin
      responses = Weather::Comparison::MODELS.to_h { |model| [model, comparison.send(:open_meteo, model, dates)] }
      comparison.send(:open_meteo_series, responses, 0)
    rescue => e
      warn "  Open-Meteo failed: #{e.message}"
      {}
    end
    classic = agweather_et(lat, lng, dates, adjusted: false)
    adjusted = agweather_et(lat, lng, dates, adjusted: true)
    wisp = series["wisp"]
    dates.each do |date|
      mm = ->(v) { v && (v * MM).round(3) }
      csv << [site, date, mm.call(wisp&.et0&.[](date)), mm.call(series["best_match"]&.et0&.[](date)), mm.call(series["wisp_2026"]&.et0&.[](date)),
        wisp&.wind&.[](date), wisp&.rh_min&.[](date), mm.call(wisp&.precip&.[](date)), mm.call(classic[date]), mm.call(adjusted[date])]
    end
  end
end
warn "wrote #{out}"

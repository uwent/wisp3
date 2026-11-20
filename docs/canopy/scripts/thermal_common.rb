# Shared by the thermal time scripts (docs/canopy/07-thermal-time.md): daily highs and lows from
# Open-Meteo's historical archive (ERA5, era5_seamless, as Weather::Normals fetches), cached as JSON
# under tmp/thermal so a rerun doesn't refetch, and the conversion of a calendar curve to degree
# days. Needs the network on the first run (scripts only; the app fetches in jobs and specs never do).
require "json"
require "fileutils"

module ThermalScripts
  CACHE = Rails.root.join("tmp/thermal")
  # Hancock Agricultural Research Station, in the Central Sands (the towers are 2–10 km away)
  HANCOCK = [44.12, -89.53].freeze
  # The archive's last day when these were run
  ARCHIVE_END = Date.new(2026, 11, 10)

  module_function

  # A crop's curve on degree days: its thermal line, or its thermal_candidate for a crop the app still
  # runs by calendar days (canopy_curves.yml), so the candidates can be checked against new readings
  def on_degree_days(key)
    curve = CanopyCurve.for(key) || CanopyCurve.generic.fetch(key)
    return curve if curve.thermal
    data = YAML.safe_load_file(CanopyCurve::FILE, aliases: true)
    sources = data.fetch("sources").to_h { |id, source| [id, CanopyCurve::Source.new(id:, **source.symbolize_keys)] }
    definition = data.fetch("crops")[key] || data.fetch("generic").fetch(key)
    CanopyCurve.new(key, definition.merge("thermal" => definition.fetch("thermal_candidate")), sources)
  end

  # {date => [tmax_f, tmin_f]} at a point, from first through last
  def temperatures(lat, lng, first, last)
    FileUtils.mkdir_p(CACHE)
    path = CACHE.join(format("%.2f_%.2f_%s_%s.json", lat, lng, first, last))
    unless File.exist?(path)
      response = Weather::OpenMeteo.new.daily([lat, lng], endpoint: :archive, model: Weather::Normals::MODEL,
        variables: Weather::Normals::VARIABLES, start_date: first, end_date: last)
      File.write(path, JSON.generate(dates: response.dates, values: response.values))
    end
    data = JSON.parse(File.read(path))
    highs, lows = data["values"].values_at(*Weather::Normals::VARIABLES)
    data["dates"].each_with_index.filter_map do |date, i|
      [Date.parse(date), [highs[i] * 9 / 5.0 + 32, lows[i] * 9 / 5.0 + 32]] if highs[i] && lows[i]
    end.to_h
  end

  # Normals as Weather::Normals computes them, from the 20 years before year: {day_of_year => [tmax_f, tmin_f]}
  def normals(lat, lng, year)
    past = temperatures(lat, lng, Date.new(year - 20, 1, 1), Date.new(year - 1, 12, 31))
    dates = past.keys
    Weather::Normals.compute(dates, *[0, 1].map { |i| dates.map { |date| (past[date][i] - 32) * 5 / 9.0 } })
  end

  # CellTemperatures at a point for a season: the year's observed days (through observed_through;
  # later days take the normals, as beyond a forecast), and normals from the 20 years before
  def cell_temperatures(lat, lng, year, observed_through: Date.new(year, 12, 31))
    last = [Date.new(year, 12, 31), ARCHIVE_END].min
    season = temperatures(lat, lng, Date.new(year, 1, 1), last).select { |date, _| date <= observed_through }
    CellTemperatures.new(season, normals(lat, lng, year))
  end

  def growth(curve, t, rate)
    cc = curve.cc0 * Math.exp(rate * t)
    cc = curve.ccx - 0.25 * curve.ccx**2 / curve.cc0 * Math.exp(-rate * t) if cc > curve.ccx / 2
    cc.clamp(0.0, curve.ccx)
  end

  # A curve's thermal parameters for base and upper (°C) and a typical emergence ("05-15"), from the
  # weather at point over years (thermal_curves.rb explains), and {per_day:, days80:} for its table
  def calibrate(curve, base, upper, emergence, years, point: HANCOCK)
    temperatures = temperatures(*point, Date.new(years.first, 1, 1), Date.new(years.last, 12, 31))
    month, day = emergence.split("-").map(&:to_i)
    horizon = [curve.full_day + 10, curve.season_days || 0, (curve.decline&.dig(:start_day) || 0) + 30].max
    # Degree days from emergence to each day after it, each year
    sums = years.map do |year|
      start = Date.new(year, month, day)
      (0..horizon).each_with_object([0.0]) do |t, acc|
        acc << acc.last + Weather::DegreeDays.aquacrop(*temperatures.fetch(start + t), base_c: base, upper_c: upper)
      end
    end
    days = (0..curve.full_day + 5).to_a
    cost = ->(rate) { sums.sum { |sum| days.sum { |t| (growth(curve, sum[t], rate) - growth(curve, t, curve.cgc))**2 } } }
    # Golden section search on log rate, between 1/60 and 1/2 of the calendar rate
    low, high = Math.log(curve.cgc / 60), Math.log(curve.cgc / 2)
    60.times do
      a, b = high - (high - low) * 0.618, low + (high - low) * 0.618
      (cost.call(Math.exp(a)) < cost.call(Math.exp(b))) ? high = b : low = a
    end
    rate = Math.exp((low + high) / 2)
    thermal = {"base_c" => base, "upper_c" => upper, "cgc" => rate.round(6)}
    if curve.decline&.fetch(:type) == "aquacrop"
      start_day = curve.decline.fetch(:start_day)
      finish = [curve.season_days || 0, start_day + 20].max
      thermal["decline_start"] = (sums.sum { |sum| sum[start_day] } / sums.size).round
      per_day = sums.sum { |sum| (sum[finish] - sum[start_day]) / (finish - start_day) } / sums.size
      thermal["cdc"] = (curve.decline.fetch(:cdc) / per_day).round(6)
    end
    thermal["emergence"] = emergence
    per_day = sums.sum { |sum| sum[curve.full_day] / curve.full_day } / sums.size
    days80 = sums.map { |sum| (0..horizon).find { |t| growth(curve, sum[t], rate) >= 0.8 * curve.ccx } }
    [thermal, {per_day:, days80:}]
  end
end

# Potato's canopy curve in calendar days and in degree days against the four Central Sands tower
# seasons with recorded cover (docs/canopy/07-thermal-time.md; the seasons are in
# docs/et-validation/06-season.md), and the crop ET each gives against the closure-corrected towers.
#
#   bin/rails runner docs/canopy/scripts/thermal_towers.rb [DIR]
#
# DIR defaults to tmp/ameriflux: daily.csv (docs/et-validation/scripts/et0.py) and desai/seasons.csv,
# desai/canopy_cover.csv (season_data.py; Desai's group's data, not published, so not in the
# repository). Temperatures at each tower from Open-Meteo's archive (thermal_common.rb), the season's
# days observed and normals from the 20 years before, as WISP would have them at season's end. ET as
# in season.rb: CropEt.from_pct_cover on the tower's own ET0 with potato's Kc mid adjusted for wind
# and RH (C21), the same days kept, closure-corrected per site and phase.
require "csv"
require_relative "thermal_common"

dir = ARGV[0] || "tmp/ameriflux"
MM_PER_IN = 25.4
POTATO = YAML.load_file(Rails.root.join("db/reference/plants.yml")).find { |p| p["key"] == "potato" }
U2_PER_U10 = Weather::Fao56.wind_speed_2m(1.0)
# docs/et-validation/scripts/weather_at_towers.rb
TOWERS = {"US-CS1" => [44.1031, -89.5379], "US-CS3" => [44.1394, -89.5727], "US-CS4" => [44.1597, -89.5475],
          "US-CS5" => [44.1095, -89.5377]}.freeze

data = YAML.safe_load_file(CanopyCurve::FILE, aliases: true)
SOURCES = data.fetch("sources").to_h { |id, source| [id, CanopyCurve::Source.new(id:, **source.symbolize_keys)] }
POTATO_CURVE = data.fetch("crops").fetch("potato")
# Potato's curve with other thermal parameters
def variant(thermal) = CanopyCurve.new("potato", POTATO_CURVE.merge("thermal" => POTATO_CURVE["thermal"].merge(thermal)), SOURCES)

base7, = ThermalScripts.calibrate(CanopyCurve.for("potato"), 7, 30, "05-15", 2006..2025)
CURVES = {
  "calendar" => [CanopyCurve.for("potato"), false],
  "GDD (WISP: base 2 °C)" => [CanopyCurve.for("potato"), true],
  "GDD, base 7 °C" => [variant(base7.slice("base_c", "upper_c", "cgc")), true],
  "AquaCrop PotatoGDD file" => [variant("cgc" => 0.01615), true],
  "AquaCrop PotatoLocalGDD file" => [variant("cgc" => 0.009653), true]
}.freeze

num = ->(v) { (v.nil? || v == "") ? nil : v.to_f }
days = CSV.read(File.join(dir, "daily.csv"), headers: true).group_by { |r| r["site"] }
seasons = CSV.read(File.join(dir, "desai/seasons.csv"), headers: true).select { |s| s["emergence"] && TOWERS[s["site"]] }
cover = CSV.read(File.join(dir, "desai/canopy_cover.csv"), headers: true).group_by { |r| r["site"] }

def interpolate(points, date)
  after = points.index { |d, _| d >= date }
  return points.last.last unless after
  return points[after].last if points[after].first == date || after.zero?
  (d0, v0), (d1, v1) = points[after - 1], points[after]
  v0 + (v1 - v0) * (date - d0) / (d1 - d0)
end

def phase(s, date)
  if date < s[:full_start] then "development"
  elsif date <= s[:full_end] then "full cover"
  elsif date < s[:vine_kill] then "decline"
  else "vine kill to harvest"
  end
end

# Days from emergence until cover first reaches pct
def reaches(emergence, pct, &cover) = (0..150).find { |t| cover.call(emergence + t) >= pct }

timing = []
rows = []
seasons.each do |s|
  site = s["site"]
  lat, lng = TOWERS.fetch(site)
  season = {emergence: Date.parse(s["emergence"]), full_start: Date.parse(s["full_cover_start"]),
            full_end: Date.parse(s["full_cover_end"]), vine_kill: Date.parse(s["vine_kill"]), harvest: Date.parse(s["harvest"])}
  em = season[:emergence]
  temperatures = ThermalScripts.cell_temperatures(lat, lng, em.year)
  measured = cover[site].map { |r| [Date.parse(r["date"]), r["canopy_cover_pct"].to_f] }.sort
  weekly = measured.select { |d, _| d >= em + 7 && d < season[:vine_kill] && ((d - em).to_i % 7).zero? }
  canopies = CURVES.to_h do |name, (curve, thermal)|
    clock = thermal ? curve.clock(temperatures) : nil
    fit_curve = ->(stretch: 1.0, **fit) { curve.from(em, stretch:, clock:, **fit) }
    make = ->(observations) {
      Canopy.new(emergence_date: em, end_date: season[:harvest], observations:, curve: fit_curve.call, fit_curve:,
        vine_kill: season[:vine_kill])
    }
    [name, {curve: make.call([]), readings: make.call(weekly)}]
  end
  gdd = temperatures.thermal_time(base_c: 2, upper_c: 26)
  timing << {site:, emergence: em, gdd30: gdd.between(em, em + 30),
             measured: [10, 50, 80].map { |pct| reaches(em, pct) { |d| interpolate(measured, d) } },
             **CURVES.keys.to_h { |name| [name, [10, 50, 80].map { |pct| reaches(em, pct) { |d| canopies[name][:curve].on(d) } }] }}

  days[site].each do |r|
    date = Date.parse(r["date"])
    next unless date.between?(em, season[:harvest])
    et0 = num.call(r["et0_mm"])
    next if et0.nil? || num.call(r["et_mm"]).nil? || num.call(r["inputs_measured"]) < 0.9 || num.call(r["le_measured"]) < 0.4 || et0 < 1
    kc = CropEt.kc_mid(POTATO["kc_mid"], POTATO["crop_height_m"],
      wind_mph: r["u2_mean_m_s"].to_f / U2_PER_U10 / CropEt::MPH_TO_MS, rh_min_pct: num.call(r["rh_min_pct"]))
    crop = ->(pct) { CropEt.from_pct_cover(et0 / MM_PER_IN, pct, kc:) * MM_PER_IN }
    row = {site:, date:, phase: phase(season, date), et0:, et: num.call(r["et_mm"]), rn: num.call(r["rn_mj"]),
           g: num.call(r["g_mj"]), h: num.call(r["h_mj"]), le: num.call(r["le_mj"])}
    row["measured cover"] = crop.call(interpolate(measured, date))
    canopies.each do |name, canopy|
      row[name] = crop.call(canopy[:curve].on(date))
      row["#{name} + weekly readings"] = crop.call(canopy[:readings].on(date))
    end
    rows << row
  end
end

closure = rows.group_by { |r| [r[:site], r[:phase]] }.transform_values do |rs|
  eb = rs.select { |r| r[:rn] && r[:h] && r[:le] }
  avail = eb.sum { |r| r[:rn] - (r[:g] || 0) }
  avail.positive? ? eb.sum { |r| r[:h] + r[:le] } / avail : nil
end
rows.each { |r| r[:corrected] = closure[[r[:site], r[:phase]]] && r[:et] / closure[[r[:site], r[:phase]]] }
rows.select! { |r| r[:corrected] }

fmt = ->(t) { t.map { |x| x || "–" }.join(" / ") }
puts "## Days from emergence to 10 / 50 / 80% cover\n\n"
puts "| Site | Emergence | °C days (base 2) in the first 30 days | Measured | #{CURVES.keys.join(" | ")} |"
puts "|---|---|---|---|#{"---|" * CURVES.size}"
timing.each do |t|
  puts "| #{t[:site]} | #{t[:emergence].strftime("%b %-d")} | #{t[:gdd30].round} | #{fmt.call(t[:measured])} | " +
    CURVES.keys.map { |name| fmt.call(t[name]) }.join(" | ") + " |"
end
puts "\nError in days, curve − measured, over the #{timing.size} seasons: mean absolute (mean)\n\n"
puts "| Curve | 10, 50 and 80% | 50 and 80% |"
puts "|---|---|---|"
CURVES.each_key do |name|
  cells = [0..2, 1..2].map do |thresholds|
    errors = timing.flat_map { |t| t[name][thresholds].zip(t[:measured][thresholds]).filter_map { |m, o| m - o if m && o } }
    "#{(errors.sum { |e| e.abs }.to_f / errors.size).round(1)} (#{format("%+.1f", errors.sum.to_f / errors.size)})"
  end
  puts "| #{name} | #{cells.join(" | ")} |"
end

columns = ["measured cover"] + CURVES.keys.flat_map { |name| [name, "#{name} + weekly readings"] }
bias = ->(rs, k) { format("%+.0f%%", 100 * (rs.sum { |r| r[k] } / rs.sum { |r| r[:corrected] } - 1)) }
puts "\n## Crop ET against the closure-corrected towers, by phase (all four seasons)\n\n"
puts "| Canopy | #{%w[development full\ cover decline vine\ kill\ to\ harvest season].join(" | ")} |"
puts "|---|---|---|---|---|---|"
columns.each do |name|
  cells = ["development", "full cover", "decline", "vine kill to harvest"].map { |ph| bias.call(rows.select { |r| r[:phase] == ph }, name) }
  puts "| #{name} | #{cells.join(" | ")} | #{bias.call(rows, name)} |"
end
puts "\n#{rows.size} days kept. Development by site (curve only):\n\n"
puts "| Site | #{CURVES.keys.join(" | ")} |"
puts "|---|#{"---|" * CURVES.size}"
rows.group_by { |r| r[:site] }.each do |site, rs|
  dev = rs.select { |r| r[:phase] == "development" }
  puts "| #{site} | #{CURVES.keys.map { |name| bias.call(dev, name) }.join(" | ")} |"
end

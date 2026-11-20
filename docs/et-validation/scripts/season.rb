# WISP 3's crop ET through the whole potato season against the Central Sands towers
# (docs/et-validation/06-season.md), with WISP's own CanopyCurve, Canopy and CropEt.
#
#   bin/rails runner docs/et-validation/scripts/season.rb [DIR]
#
# DIR defaults to tmp/ameriflux: daily.csv (et0.py) and desai/seasons.csv, desai/canopy_cover.csv
# (season_data.py). Writes DIR/season_daily.csv and prints the tables in note 06. Days are kept as in
# compare.py (90% of half-hours with every ET0 input measured, 40% with LE measured, ET0 ≥ 1 mm).
#
# ET0 is the tower's own (et0.py), so this tests the crop side of WISP, not its weather. Crop ET is
# computed two ways, each from three canopies:
# - before C22 ("old"): CropEt.from_pct_cover with potato's Kc mid adjusted each day for wind and
#   minimum RH (C21);
# - C22 ("dual"): FAO-56's dual crop coefficient as WaterBalance runs it, Kcb from the canopy
#   (CropEt.kcb, potato's Table 17 values easing to Kcb end at harvest after the curve's decline
#   start, WaterBalance::Crop) plus soil evaporation (SoilEvaporation, carried day by day from
#   emergence, wetted by the tower's own rain gauge, which catches the pivot's water too, fw 1). It's
#   run on sand's and loamy sand's soil values (soil_types.yml), the Central Sands' two textures.
# The canopies:
# - measured: Desai's group's cover, linear between their values (the test of CropEt's cover to
#   crop coefficient relation, apart from the canopy's timing);
# - curve: what a grower gets entering emergence, vine kill and harvest and no readings (potato's
#   curve, its July 25 decline rule, the vine kill ramp);
# - readings: the same with a reading each week to vine kill, taken from the measured cover.
# Measured ET is corrected for energy balance closure per site and phase, as in 03 (Bowen ratio kept).
require "csv"
require "yaml"

dir = ARGV[0] || "tmp/ameriflux"
MM_PER_IN = 25.4
REFERENCE = Rails.root.join("db/reference")
POTATO = YAML.load_file(REFERENCE.join("plants.yml")).find { |p| p["key"] == "potato" }
SOILS = YAML.load_file(REFERENCE.join("soil_types.yml")).select { |s| %w[sand loamy_sand].include?(s["key"]) }
  .to_h { |s| [s["key"], SoilEvaporation.new(tew: SoilEvaporation.tew(s["field_capacity"], s["perm_wilting_pt"]), rew: s["rew_in"])] }
CANOPIES = %i[measured_cover curve readings]
CURVE = CanopyCurve.for("potato")
U2_PER_U10 = Weather::Fao56.wind_speed_2m(1.0)
OBSERVED = %w[US-CS4 US-CS5] # cover observed day by day; 2018 and 2019's is a template between phases

num = ->(v) { (v.nil? || v == "") ? nil : v.to_f }
days = CSV.read(File.join(dir, "daily.csv"), headers: true).group_by { |r| r["site"] }
seasons = CSV.read(File.join(dir, "desai/seasons.csv"), headers: true).select { |s| s["emergence"] }
cover = CSV.read(File.join(dir, "desai/canopy_cover.csv"), headers: true).group_by { |r| r["site"] }

def interpolate(points, date)
  after = points.index { |d, _| d >= date }
  return points.last.last unless after # after the last value (bare ground), held
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

rows = []
seasons.each do |s|
  site = s["site"]
  season = {emergence: Date.parse(s["emergence"]), full_start: Date.parse(s["full_cover_start"]),
            full_end: Date.parse(s["full_cover_end"]), vine_kill: Date.parse(s["vine_kill"]), harvest: Date.parse(s["harvest"])}
  measured = cover[site].map { |r| [Date.parse(r["date"]), r["canopy_cover_pct"].to_f] }.sort
  fit_curve = ->(stretch: 1.0, **fit) { CURVE.from(season[:emergence], stretch:, **fit) }
  canopy = ->(observations) {
    Canopy.new(emergence_date: season[:emergence], end_date: season[:harvest], observations:, curve: fit_curve.call,
      fit_curve:, vine_kill: season[:vine_kill])
  }
  curve = canopy.call([])
  weekly = measured.select { |d, _| d >= season[:emergence] + 7 && d < season[:vine_kill] && ((d - season[:emergence]).to_i % 7).zero? }
  readings = canopy.call(weekly)

  crop = WaterBalance::Crop.new(kcb_mid: POTATO["kcb_mid"], kcb_end: POTATO["kcb_end"], height_m: POTATO["crop_height_m"],
    late_start: CURVE.decline_start(season[:emergence]), end_date: season[:harvest])
  # The surface layer per canopy and soil, carried through every day of the season (kept or not)
  surfaces = CANOPIES.product(SOILS.keys).to_h { |key| [key, SoilEvaporation::State.initial] }
  by_date = days[site].index_by { |r| r["date"] }

  (season[:emergence]..season[:harvest]).each do |date|
    r = by_date[date.iso8601]
    et0 = r && num.call(r["et0_mm"])
    next unless et0 # no ET0: the layer is left as it was, as WaterBalance does

    weather = {wind_mph: r["u2_mean_m_s"].to_f / U2_PER_U10 / CropEt::MPH_TO_MS, rh_min_pct: num.call(r["rh_min_pct"])}
    kc = CropEt.kc_mid(POTATO["kc_mid"], POTATO["crop_height_m"], **weather)
    old = ->(pct) { pct && CropEt.from_pct_cover(et0 / MM_PER_IN, pct, kc:) * MM_PER_IN }
    covers = {measured_cover: interpolate(measured, date), curve: curve.on(date), readings: readings.on(date)}
    kcb_full = crop.kcb_full(date, **weather)
    dual = covers.flat_map do |canopy, pct|
      kcb = CropEt.kcb("pct_cover", kcb_full, pct, crop.height_m)
      SOILS.map do |soil, layer|
        step = layer.step(surfaces[[canopy, soil]], et0: et0 / MM_PER_IN, kcb:, kc_max: CropEt.kc_max(kcb, crop.height_m, **weather),
          cover: pct / 100.0, rain: num.call(r["p_mm"]).to_f / MM_PER_IN)
        surfaces[[canopy, soil]] = step.state
        [:"dual_#{canopy}_#{soil}", (kcb + step.ke) * et0]
      end
    end.to_h

    et = num.call(r["et_mm"])
    next if et.nil? || num.call(r["inputs_measured"]) < 0.9 || num.call(r["le_measured"]) < 0.4 || et0 < 1

    prev = by_date[(date - 1).iso8601]
    rows << {
      site:, date:, phase: phase(season, date), et0:, et:, rn: num.call(r["rn_mj"]), g: num.call(r["g_mj"]),
      h: num.call(r["h_mj"]), le: num.call(r["le_mj"]), wet: [r, prev].compact.any? { |x| num.call(x["p_mm"]).to_f > 0.5 },
      cover_measured: covers[:measured_cover], cover_curve: covers[:curve], cover_readings: covers[:readings], kc:,
      et_measured_cover: old.call(covers[:measured_cover]), et_curve: old.call(covers[:curve]), et_readings: old.call(covers[:readings]),
      **dual
    }
  end
end

# Closure per site and phase, C = Σ(H + LE) / Σ(Rn − G), G taken as 0 where it isn't measured
closure = rows.group_by { |r| [r[:site], r[:phase]] }.transform_values do |rs|
  eb = rs.select { |r| r[:rn] && r[:h] && r[:le] }
  avail = eb.sum { |r| r[:rn] - (r[:g] || 0) }
  avail.positive? ? eb.sum { |r| r[:h] + r[:le] } / avail : nil
end
rows.each { |r| r[:et_corrected] = closure[[r[:site], r[:phase]]] && r[:et] / closure[[r[:site], r[:phase]]] }

CSV.open(File.join(dir, "season_daily.csv"), "w") do |csv|
  keys = rows.first.keys
  csv << keys
  rows.each { |r| csv << keys.map { |k| r[k].is_a?(Float) ? r[k].round(3) : r[k] } }
end

ratio = ->(rs, k) { rs.sum { |r| r[k] } / rs.sum { |r| r[:et0] } }
bias = ->(rs, k) { format("%+.0f%%", 100 * (rs.sum { |r| r[k] } / rs.sum { |r| r[:et_corrected] } - 1)) }
f2 = ->(x) { x ? format("%.2f", x) : "–" }
PHASES = ["development", "full cover", "decline", "vine kill to harvest"]

MODELS = CANOPIES.map { |c| [:"et_#{c}", "old, #{c.to_s.tr("_", " ")}"] } +
  SOILS.keys.flat_map { |soil| CANOPIES.map { |c| [:"dual_#{c}_#{soil}", "C22 #{soil.tr("_", " ")}, #{c.to_s.tr("_", " ")}"] } }
cell = ->(xs, k) { "#{f2.call(ratio.call(xs, k))} (#{bias.call(xs, k)})" }

puts "## Summary: ET / ET0 by phase (bias against closure-corrected ET), all sites\n\n"
puts "| Phase | Days | Corrected | #{MODELS.map(&:last).join(" | ")} |"
puts "|" + "---|" * (MODELS.size + 3)
(PHASES + [nil]).each do |ph|
  xs = rows.select { |r| (ph.nil? || r[:phase] == ph) && r[:et_corrected] }
  puts "| #{ph || "**Season**"} | #{xs.size} | #{f2.call(ratio.call(xs, :et_corrected))} | #{MODELS.map { |k, _| cell.call(xs, k) }.join(" | ")} |"
end

puts "\n## C22 by site and phase (ET / ET0)\n\n"
puts "| Site | Phase | Days | Corrected | #{MODELS.map(&:last).join(" | ")} |"
puts "|" + "---|" * (MODELS.size + 4)
rows.group_by { |r| r[:site] }.each do |site, rs|
  PHASES.each do |ph|
    xs = rs.select { |r| r[:phase] == ph && r[:et_corrected] }
    next if xs.empty?
    puts "| #{site} | #{ph} | #{xs.size} | #{f2.call(ratio.call(xs, :et_corrected))} | #{MODELS.map { |k, _| f2.call(ratio.call(xs, k)) }.join(" | ")} |"
  end
end

puts "\n## Through the summer (all sites, corrected ET / ET0 against the models, curve)\n\n"
puts "| | Days | Corrected | old, curve | C22 sand, curve | C22 loamy sand, curve |"
puts "|---|---|---|---|---|---|"
[["July 1–15", 7, 1..15], ["July 16–31", 7, 16..31], ["August 1–15", 8, 1..15], ["August 16–31", 8, 16..31]].each do |label, month, range|
  xs = rows.select { |r| r[:date].month == month && range.cover?(r[:date].day) && r[:et_corrected] && r[:phase] != "vine kill to harvest" }
  next if xs.empty?
  puts "| #{label} | #{xs.size} | #{f2.call(ratio.call(xs, :et_corrected))} | #{f2.call(ratio.call(xs, :et_curve))} | " \
    "#{f2.call(ratio.call(xs, :dual_curve_sand))} | #{f2.call(ratio.call(xs, :dual_curve_loamy_sand))} |"
end

puts "\n## After vine kill, wet and dry days (C22 against corrected, curve)\n\n"
puts "| Site | Wet days | Corrected | C22 sand | C22 loamy sand | Dry days | Corrected | C22 sand | C22 loamy sand |"
puts "|---|---|---|---|---|---|---|---|---|"
rows.select { |r| r[:phase] == "vine kill to harvest" && r[:et_corrected] }.group_by { |r| r[:site] }.each do |site, rs|
  wet, dry = rs.partition { |r| r[:wet] }
  c = ->(ys, k) { ys.empty? ? "–" : f2.call(ratio.call(ys, k)) }
  puts "| #{site} | #{wet.size} | #{c.call(wet, :et_corrected)} | #{c.call(wet, :dual_curve_sand)} | #{c.call(wet, :dual_curve_loamy_sand)} | " \
    "#{dry.size} | #{c.call(dry, :et_corrected)} | #{c.call(dry, :dual_curve_sand)} | #{c.call(dry, :dual_curve_loamy_sand)} |"
end

puts "\n## By phase\n\nET / ET0 (the crop coefficient) and bias against closure-corrected ET.\n\n"
puts "| Site | Phase | Days | ET0 mm/d | Closure | Measured | Corrected | Model, measured cover | Model, curve | Model, readings | Bias, measured cover | Bias, curve | Bias, readings |"
puts "|" + "---|" * 13
rows.group_by { |r| r[:site] }.each do |site, rs|
  PHASES.each do |ph|
    xs = rs.select { |r| r[:phase] == ph && r[:et_corrected] }
    next if xs.empty?
    puts "| #{site} | #{ph} | #{xs.size} | #{f2.call(xs.sum { |r| r[:et0] } / xs.size)} | #{f2.call(closure[[site, ph]])} | " \
      "#{f2.call(ratio.call(xs, :et))} | #{f2.call(ratio.call(xs, :et_corrected))} | #{f2.call(ratio.call(xs, :et_measured_cover))} | " \
      "#{f2.call(ratio.call(xs, :et_curve))} | #{f2.call(ratio.call(xs, :et_readings))} | " \
      "#{bias.call(xs, :et_measured_cover)} | #{bias.call(xs, :et_curve)} | #{bias.call(xs, :et_readings)} |"
  end
end
PHASES.each do |ph|
  xs = rows.select { |r| r[:phase] == ph && r[:et_corrected] }
  puts "| **All** | #{ph} | #{xs.size} | #{f2.call(xs.sum { |r| r[:et0] } / xs.size)} | – | #{f2.call(ratio.call(xs, :et))} | " \
    "#{f2.call(ratio.call(xs, :et_corrected))} | #{f2.call(ratio.call(xs, :et_measured_cover))} | #{f2.call(ratio.call(xs, :et_curve))} | " \
    "#{f2.call(ratio.call(xs, :et_readings))} | #{bias.call(xs, :et_measured_cover)} | #{bias.call(xs, :et_curve)} | #{bias.call(xs, :et_readings)} |"
end

puts "\n## Season totals (kept days, emergence to harvest), mm\n\n"
puts "| Site | Days | Measured | Corrected | Model, measured cover | Model, curve | Model, readings |"
puts "|---|---|---|---|---|---|---|"
(rows.group_by { |r| r[:site] }.to_a + [["**All**", rows]]).each do |site, rs|
  xs = rs.select { |r| r[:et_corrected] }
  sum = ->(k) { format("%.0f", xs.sum { |r| r[k] }) }
  puts "| #{site} | #{xs.size} | #{sum.call(:et)} | #{sum.call(:et_corrected)} | #{sum.call(:et_measured_cover)} (#{bias.call(xs, :et_measured_cover)}) | " \
    "#{sum.call(:et_curve)} (#{bias.call(xs, :et_curve)}) | #{sum.call(:et_readings)} (#{bias.call(xs, :et_readings)}) |"
end

puts "\n## Crop coefficient by measured cover (#{OBSERVED.join(", ")}, emergence to vine kill)\n\n"
puts "Corrected uses each day's site-and-phase closure. Wet: rain or irrigation over 0.5 mm that day or the day before.\n\n"
puts "| Cover % | Days | Wet days | Measured | Corrected | Corrected, wet | Corrected, dry | Old (C21) | C22 sand | C22 loamy sand | C22 sand, wet | C22 sand, dry |"
puts "|---|---|---|---|---|---|---|---|---|---|---|---|"
[[0, 10], [10, 30], [30, 50], [50, 80], [80, 100], [100, 101]].each do |lo, hi|
  xs = rows.select { |r| OBSERVED.include?(r[:site]) && r[:phase] != "vine kill to harvest" && r[:et_corrected] && r[:cover_measured]&.then { |c| c >= lo && c < hi } }
  next if xs.empty?
  wet, dry = xs.partition { |r| r[:wet] }
  c = ->(ys) { ys.empty? ? "–" : f2.call(ratio.call(ys, :et_corrected)) }
  m = ->(ys, k) { ys.empty? ? "–" : f2.call(ratio.call(ys, k)) }
  puts "| #{(hi > 100) ? "100" : "#{lo}–#{hi}"} | #{xs.size} | #{wet.size} | #{f2.call(ratio.call(xs, :et))} | #{c.call(xs)} | #{c.call(wet)} | #{c.call(dry)} | " \
    "#{m.call(xs, :et_measured_cover)} | #{m.call(xs, :dual_measured_cover_sand)} | #{m.call(xs, :dual_measured_cover_loamy_sand)} | " \
    "#{m.call(wet, :dual_measured_cover_sand)} | #{m.call(dry, :dual_measured_cover_sand)} |"
end

puts "\n## Canopy: curve against measured cover, by phase (mean %)\n\n"
puts "| Site | Development | Full cover | Decline | Vine kill to harvest |"
puts "|---|---|---|---|---|"
rows.group_by { |r| r[:site] }.each do |site, rs|
  cells = PHASES.map do |ph|
    xs = rs.select { |r| r[:phase] == ph && r[:cover_measured] }
    xs.empty? ? "–" : format("%.0f / %.0f", xs.sum { |r| r[:cover_measured] } / xs.size, xs.sum { |r| r[:cover_curve] } / xs.size)
  end
  puts "| #{site} | #{cells.join(" | ")} |"
end
warn "wrote #{File.join(dir, "season_daily.csv")} (#{rows.size} days)"

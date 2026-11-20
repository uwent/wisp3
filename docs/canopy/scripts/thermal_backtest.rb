# The backtest of docs/canopy/04 and 06 on the canopy curves in calendar days and in degree days
# (docs/canopy/07-thermal-time.md), through WISP's own Canopy, CanopyCurve and CanopyFit.
#
#   bin/rails runner docs/canopy/scripts/thermal_backtest.rb CSV
#
# CSV: the legacy WISP 2026 percent cover readings (legacy_canopy_export.rb; not committed), with
# each series' location rounded to 0.1°. The 37 screened series are chosen as backtest.py does.
# Temperatures at each location from Open-Meteo's archive (thermal_common.rb): 2026 as observed,
# normals from 2006–2025. Errors are in crop ET as a fraction of ET0 (CropEt at ET0 0.2 in, so misses
# above 80% cover cost nothing), with cover points in brackets, as in 04.
require "csv"
require_relative "thermal_common"

path = ARGV[0] or abort "usage: bin/rails runner #{__FILE__} legacy_canopy_export.csv"
CROPS = {"Potato" => "potato", "Field Corn" => "field_corn", "Soybean" => "soybean", "Snap bean" => "snap_bean",
         "Shell peas" => "shell_peas", "Sweet Corn" => "sweet_corn"}.freeze

series = []
seen = Set.new
CSV.read(path, headers: true).group_by { |r| r["planting"] }.each_value do |rows|
  r0 = rows.first
  next unless CROPS[r0["crop"]] && r0["default_emergence"] != "true"
  em = Date.parse(r0["emergence_date"])
  points = rows.map { |r| [Date.parse(r["date"]), r["pct_cover"].to_f] }.sort
  signature = [r0["crop"], em, r0["lat"], r0["lon"], points.first(5).map(&:last)]
  next if seen.include?(signature) || points.count { |_, c| c < 80 } < 3
  seen << signature
  series << {crop: CROPS[r0["crop"]], emergence: em, lat: r0["lat"].to_f, lng: r0["lon"].to_f, points:}
end
puts "#{series.size} series: #{series.group_by { |s| s[:crop] }.map { |c, ss| "#{c} #{ss.size}" }.join(", ")}\n\n"

temperatures = {}
ratio = ->(c) { CropEt.from_pct_cover(0.2, c) / 0.2 }

# A canopy for a series from readings known, in calendar days or degree days
canopy = lambda do |s, known, thermal|
  curve = thermal ? ThermalScripts.on_degree_days(s[:crop]) : CanopyCurve.for(s[:crop])
  cell = temperatures[[s[:lat], s[:lng]]] ||= ThermalScripts.cell_temperatures(s[:lat], s[:lng], s[:emergence].year)
  clock = thermal ? curve.clock(cell) : nil
  em = s[:emergence]
  fit_curve = ->(stretch: 1.0, **fit) { curve.from(em, stretch:, clock:, **fit) }
  Canopy.new(emergence_date: em, end_date: em + 150, observations: known, curve: fit_curve.call, fit_curve:)
end

METHODS = {
  "calendar, curve only" => [false, false], "GDD, curve only" => [true, false],
  "calendar, fitted + ratio fading (WISP)" => [false, true], "GDD, fitted + ratio fading" => [true, true]
}.freeze

def mean(xs) = xs.sum.to_f / xs.size

results = METHODS.to_h { |name, _| [name, Hash.new { |h, k| h[k] = {forward: [], rest: [], interpolate: []} }] }
series.each do |s|
  pts = s[:points]
  METHODS.each do |name, (thermal, readings)|
    out = results[name][s[:crop]]
    predict = ->(known) { canopy.call(s, readings ? known : [], thermal) }
    err = ->(c, date, value) { [(ratio.call(c.on(date)) - ratio.call(value)).abs, (c.on(date) - value).abs] }
    (1...pts.size).each do |k|
      break if pts[k - 1][1] >= 80
      c = predict.call(pts.first(k))
      out[:forward] << err.call(c, *pts[k])
      out[:rest].concat(pts[k..].map { |date, value| err.call(c, date, value) })
    end
    c = predict.call(pts.each_slice(2).map(&:first))
    out[:interpolate].concat(pts.each_slice(2).filter_map { |pair| pair[1] }.map { |date, value| err.call(c, date, value) })
  end
end

crops = series.map { |s| s[:crop] }.uniq.sort
%i[forward rest interpolate].each do |test|
  puts "## #{test}: mean |error| in ET/ET0 (cover points)\n\n"
  puts "| Method | #{crops.join(" | ")} | All |"
  puts "|---|#{"---|" * (crops.size + 1)}"
  results.each do |name, by_crop|
    cells = crops.map { |crop| by_crop[crop][test].then { |e| "#{format("%.3f", mean(e.map(&:first)))} (#{mean(e.map(&:last)).round})" } }
    all = crops.flat_map { |crop| by_crop[crop][test] }
    puts "| #{name} | #{cells.join(" | ")} | **#{format("%.3f", mean(all.map(&:first)))}** (#{mean(all.map(&:last)).round}) |"
  end
  puts
end

# Days from emergence to 50% and 80% cover, read (linear between readings) against each curve alone
crossing = ->(pts, pct) do
  pts.each_cons(2) { |(d0, c0), (d1, c1)| return d0 + (pct - c0) * (d1 - d0) / (c1 - c0) if c0 < pct && c1 >= pct }
  nil
end
puts "## Days to 50% and 80% cover: curve − readings, mean (mean absolute, SD)\n\n"
puts "| Crop | Series | Calendar | GDD |"
puts "|---|---|---|---|"
by_crop = series.group_by { |s| s[:crop] }
(by_crop.to_a + [["All", series]]).each do |crop, ss|
  cells = [false, true].map do |thermal|
    errors = ss.flat_map do |s|
      c = canopy.call(s, [], thermal)
      [50, 80].filter_map do |pct|
        read = crossing.call([[s[:emergence], 0.0]] + s[:points], pct) or next
        model = (0..150).find { |t| c.on(s[:emergence] + t) >= pct } or next
        model - (read - s[:emergence]).to_f
      end
    end
    sd = Math.sqrt(mean(errors.map { |e| (e - mean(errors))**2 }))
    "#{format("%+.1f", mean(errors))} (#{mean(errors.map(&:abs)).round(1)}, SD #{sd.round(1)})"
  end
  puts "| #{crop} | #{ss.size} | #{cells.join(" | ")} |"
end

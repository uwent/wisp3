# Converts each canopy curve's calendar parameters to degree days (docs/canopy/07-thermal-time.md,
# PLAN.md §9 C23), and prints the `thermal:` line for db/reference/canopy_curves.yml.
#
#   bin/rails runner docs/canopy/scripts/thermal_curves.rb
#
# For each curve: the base and upper temperatures (AquaCrop's crop file where there is one, FAO-56
# Rev.1 Table 6.10 for potato, else an assumption, below) and a typical Wisconsin emergence date.
# Over each of the 20 years 2006–2025 at Hancock (Central Sands; Open-Meteo's ERA5 archive, thermal_common.rb), the curve emerges on that
# date and degree days are summed from it by AquaCrop's method 3 (Weather::DegreeDays.aquacrop).
# Growth: the coefficient per degree day (CC₀ and CCx kept) that best matches the calendar curve from
# emergence to full cover, all years together (least squares in cover). Decline (aquacrop): its start
# is the mean degree days to the calendar start day, and its coefficient the calendar one over the
# mean degree days a day from the start to the season's end. So in a typical season the thermal curve
# is the calendar one; in a warm one it runs ahead, in a cool one behind.
require_relative "thermal_common"

YEARS = 2006..2025

AQUACROP = "from AquaCrop's %s crop file"
COOL = "assumed for cool-season vegetables (40 °F, the base of pea heat units; upper as AquaCrop's potato and wheat)"
WARM = "assumed for warm-season vegetables (50 °F, the usual base for cucurbits and sweet potato; upper as AquaCrop's warm-season crops)"
DEFAULT = "from AquaCrop's default crop file"
# curve key => [base °C, upper °C, where they're from, typical emergence (month-day), why that date]
CROPS = {
  "potato" => [2, 30, "from FAO-56 Rev.1 Table 6.10 (the same base as AquaCrop's potato crop file, whose upper is 26 °C)", "05-15", "Central Sands plantings from mid-April to mid-May; 2026 readings' median May 19"],
  "field_corn" => [8, 30, AQUACROP % "maize", "05-15", "2026 readings' median May 18"],
  "corn_silage" => [8, 30, AQUACROP % "maize", "05-15", "as field corn"],
  "sweet_corn" => [8, 30, AQUACROP % "maize", "06-01", "processing plantings from May into June; 2026 readings May 22 and June 9"],
  "soybean" => [5, 30, AQUACROP % "soybean", "05-20", "2026 readings May 14–24"],
  "snap_bean" => [9, 30, AQUACROP % "dry bean", "06-15", "processing plantings from May to July; 2026 readings May 18 to July 24"],
  "dry_bean" => [9, 30, AQUACROP % "dry bean", "06-05", "planted late May to early June"],
  "shell_peas" => [4.4, 26, COOL, "05-05", "2026 readings May 3–11"],
  "tomato" => [7, 28, AQUACROP % "tomato", "06-01", "transplanted late May to early June"],
  "pepper" => [7, 28, AQUACROP % "tomato" + " (assumed for pepper)", "06-01", "transplanted late May to early June"],
  "barley" => [0, 15, AQUACROP % "barley", "04-25", "spring small grains planted in April"],
  "wheat" => [0, 26, AQUACROP % "wheat", "04-25", "spring wheat planted in April"],
  "oats" => [0, 26, AQUACROP % "wheat" + " (assumed for oats)", "04-25", "oats planted mid-April to mid-May (UW trials)"],
  "cabbage" => [4.4, 26, COOL, "05-20", "transplanted in May"],
  "broccoli" => [4.4, 26, COOL, "05-20", "transplanted in May"],
  "carrot" => [4.4, 26, COOL, "05-20", "seeded in May"],
  "beets" => [4.4, 26, COOL, "05-15", "seeded in May"],
  "celery" => [4.4, 26, COOL, "06-01", "transplanted late May to early June"],
  "leafy_greens" => [4.4, 26, COOL, "05-05", "first plantings in early May"],
  "cucumber" => [10, 30, WARM, "06-05", "seeded or transplanted after frost, late May to mid-June"],
  "summer_squash" => [10, 30, WARM, "06-05", "seeded or transplanted after frost"],
  "melon" => [10, 30, WARM, "06-05", "transplanted after frost"],
  "pumpkin" => [10, 30, WARM, "06-05", "seeded late May to mid-June"],
  "winter_squash" => [10, 30, WARM, "06-05", "seeded late May to mid-June"],
  "sweet_potato" => [10, 30, WARM, "06-05", "transplanted after the soil warms"],
  "sugar_beet" => [5, 30, AQUACROP % "sugar beet", "05-05", "planted mid to late April"],
  "sorghum" => [8, 30, AQUACROP % "sorghum", "06-01", "planted when the soil reaches 60 °F"],
  "leafy_fast" => [4.4, 26, COOL, "05-05", "as leafy greens"],
  "vegetable_medium" => [5.5, 30, DEFAULT, "05-25", "a mid-May to early June planting"],
  "slow_partial" => [5.5, 30, DEFAULT, "05-01", "onions planted in April"],
  "perennial_regrowth" => [5, 30, AQUACROP % "alfalfa", "06-01", "regrowth between cuttings in early summer"]
}.freeze

curves = CanopyCurve.all.merge(CanopyCurve.generic)
results = CROPS.map do |key, (base, upper, source, emergence, why)|
  thermal, years = ThermalScripts.calibrate(curves.fetch(key), base, upper, emergence, YEARS)
  month, day = emergence.split("-").map(&:to_i)
  thermal["basis"] = "Base and upper temperatures #{source}; converted for emergence on " \
    "#{Date::MONTHNAMES[month]} #{day} (#{why})"
  [key, thermal, years]
end

# --write: puts each thermal: line in db/reference/canopy_curves.yml, after the curve's growth (and
# decline), replacing the one there and keeping its key (thermal, or thermal_candidate for a crop not
# yet on degree days)
if ARGV.include?("--write")
  lines = File.readlines(CanopyCurve::FILE)
  results.each do |key, thermal, _|
    at = lines.index("  #{key}:\n") or abort "#{key} isn't in the file"
    block = (at + 1...lines.size).take_while { |i| lines[i].start_with?("    ") }
    old = block.find { |i| lines[i].match?(/\A    thermal(_candidate)?:/) }
    name = old ? lines[old][/\A    (\w+):/, 1] : "thermal"
    lines.delete_at(old) if old
    growth = block.find { |i| lines[i].start_with?("    growth:") }
    after = lines[growth + 1].start_with?("    decline:") ? growth + 2 : growth + 1
    values = thermal.map { |name, value| "#{name}: #{value.is_a?(String) ? value.to_json : value}" }.join(", ")
    lines.insert(after, "    #{name}: {#{values}}\n")
  end
  File.write(CanopyCurve::FILE, lines.join)
  puts "Wrote #{CanopyCurve::FILE}\n\n"
end

puts "| Curve | Base, upper (°C) | Emergence | CGC per °C day | Decline start (°C days), CDC | °C days a day to full cover | Days to 80% of CCx, 2006–2025 (calendar) |"
puts "|---|---|---|---|---|---|---|"
results.each do |key, thermal, years|
  decline = thermal["decline_start"] ? "#{thermal["decline_start"]}, #{thermal["cdc"]}" : ""
  calendar = curves[key].then { |c| (0..200).find { |t| ThermalScripts.growth(c, t, c.cgc) >= 0.8 * c.ccx } }
  puts "| #{key} | #{thermal["base_c"]}, #{thermal["upper_c"]} | #{thermal["emergence"]} | #{thermal["cgc"]} | #{decline} | " \
    "#{years[:per_day].round(1)} | #{years[:days80].min}–#{years[:days80].max} (#{calendar}) |"
end

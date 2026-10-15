# Exports the percent cover readings growers entered in legacy WISP, anonymised, for fitting
# canopy curves (PLAN.md Phase 6.7, A.2). Read-only. Run on the legacy production server:
#
#   cd ~/wisp/current && RAILS_ENV=production bundle exec rails runner \
#     /path/to/legacy_canopy_export.rb ~/legacy_canopy_readings.csv
#
# Writes one row per entered reading. It leaves out users, farms, pivot and field names, notes,
# varieties (free text, mostly left at the default) and database ids. Each planting gets a number
# that is random on every run, and locations are rounded to 0.1° (about 11 km, coarser than a
# weather grid cell). Prints a summary of what was and wasn't exported. Legacy deleted each
# season's data on February 15, so only the current season is there.

require "csv"

path = ARGV.fetch(0) { abort "usage: rails runner legacy_canopy_export.rb OUTPUT.csv" }

crops = Crop.joins(field: :pivot).includes(:plant, field: :pivot).where.not(emergence_date: nil).to_a
readings = FieldDailyWeather.where(field_id: crops.map(&:field_id).uniq).where.not(entered_pct_cover: nil)
  .pluck(:field_id, :date, :entered_pct_cover).group_by(&:first)

crops_by_field = crops.group_by(&:field_id)
numbers = (1..crops.size).to_a.shuffle
summary = Hash.new { |h, k| h[k] = {plantings: 0, with_readings: 0, readings: 0} }
rows = 0

CSV.open(path, "w") do |csv|
  csv << %w[planting crop year et_method emergence_date end_date default_emergence lat lon date pct_cover]
  crops.each_with_index do |crop, i|
    field, pivot = crop.field, crop.field.pivot
    # A field's readings belong to the crop emerged most recently on or before the reading (double cropping)
    later = crops_by_field[crop.field_id].select { |c| c.emergence_date > crop.emergence_date }.map(&:emergence_date).min
    own = (readings[crop.field_id] || []).select { |_, date, _| date >= crop.emergence_date && (later.nil? || date < later) }

    key = [crop.plant&.name || "(none)", pivot.cropping_year]
    summary[key][:plantings] += 1
    next if own.empty?
    summary[key][:with_readings] += 1
    summary[key][:readings] += own.size

    default = crop.emergence_date.month == Field::EMERGENCE_DATE[0] && crop.emergence_date.day == Field::EMERGENCE_DATE[1]
    lat = pivot.latitude&.round(1)
    lon = pivot.longitude&.round(1)
    own.sort_by { |_, date, _| date }.each do |_, date, cover|
      csv << [numbers[i], crop.plant&.name, pivot.cropping_year, field.et_method,
        crop.emergence_date, crop.end_date, default, lat, lon, date, cover]
      rows += 1
    end
  end
end

puts "Wrote #{rows} readings to #{path}"
puts "crop, year: plantings / with readings / readings"
summary.sort.each { |(plant, year), s| puts "#{plant}, #{year}: #{s[:plantings]} / #{s[:with_readings]} / #{s[:readings]}" }

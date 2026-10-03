# Exports anonymized golden-test fixtures from the LEGACY app (PLAN.md §10). Read-only.
#
# Run on the legacy server, from the legacy app:
#   scp -P 216 script/legacy/export_golden_fixtures.rb deploy@<host>:/tmp/
#   cd ~/wisp/current && RAILS_ENV=production bundle exec rails runner /tmp/export_golden_fixtures.rb > /tmp/wisp_golden.json
# Options (env): YEAR (default 2026), COUNT (default 30), SEED (default 1, for a repeatable sample).
# Then in wisp3: bin/rails golden:import FILE=wisp_golden.json  (splits it into spec/fixtures/legacy/)
#
# Picks a mix: LAI fields, fields with soil moisture readings, fields with entered percent cover,
# fields in field groups, and the rest at random. Leaves out names, notes, locations and IDs.
year = Integer(ENV.fetch("YEAR", 2026))
count = Integer(ENV.fetch("COUNT", 30))
rng = Random.new(Integer(ENV.fetch("SEED", 1)))

ActiveRecord::Base.transaction do
  ActiveRecord::Base.connection.execute("SET TRANSACTION READ ONLY")

  fields = Field.joins(:pivot).where(pivots: {cropping_year: year})
    .where(id: FieldDailyWeather.where.not(ad: nil).group(:field_id).having("count(*) >= 60").select(:field_id))
    .to_a.select { |field| field.current_crop&.plant }
  in_groups = MultiEditLink.distinct.pluck(:field_id).to_set
  fdw = ->(field) { field.field_daily_weather.sort_by(&:date) }

  picked = []
  take = ->(candidates, n) { (candidates - picked).sample(n, random: rng).each { |field| picked << field } }
  take.call(fields.select { |f| f.et_method == Field::LAI_METHOD }, 6)
  take.call(fields.select { |f| fdw.call(f).any?(&:entered_pct_moisture) }, 8)
  take.call(fields.select { |f| fdw.call(f).any?(&:entered_pct_cover) }, 8)
  take.call(fields.select { |f| in_groups.include?(f.id) }, 4)
  take.call(fields, count - picked.size)

  fixtures = picked.each_with_index.map do |field, i|
    crop = field.current_crop
    {
      fixture: format("field_%02d", i + 1),
      year:,
      plant: crop.plant.name,
      et_method: (field.et_method == Field::LAI_METHOD) ? "lai" : "pct_cover",
      field_capacity: field.field_capacity, # legacy's effective values (soil default when unset)
      perm_wilting_pt: field.perm_wilting_pt,
      max_root_zone_depth: crop.max_root_zone_depth,
      mad_frac: crop.max_allowable_depletion_frac,
      target_ad_pct: field.target_ad_pct,
      initial_soil_moisture: crop.initial_soil_moisture,
      emergence_date: crop.emergence_date,
      end_date: crop.harvest_or_kill_date || crop.end_date,
      in_field_group: in_groups.include?(field.id),
      days: fdw.call(field).map do |day|
        day.attributes.slice(*%w[date ref_et rain irrigation entered_pct_moisture entered_pct_cover
          calculated_pct_cover leaf_area_index degree_days adj_et ad deep_drainage calculated_pct_moisture])
      end
    }
  end

  puts JSON.pretty_generate(fixtures)
  warn "Exported #{fixtures.size} fields from #{fields.size} candidates for #{year}"
end

require "rails_helper"

# Golden tests against legacy WISP (PLAN.md §10), on fields exported from legacy production by
# script/legacy/export_golden_fixtures.rb (bin/rails golden:import). For each field:
#
# 1. LegacyEngine, given legacy's own canopy series, reproduces legacy's AD. This checks that
#    spec/support/legacy_engine.rb really is the legacy model.
# 2. WaterBalance differs from legacy's AD only on days that a listed fix explains: removing that
#    fix from LegacyEngine (or, for C3/C4, using legacy's canopy) changes the day.
#
# Both start from legacy's AD on the first day: legacy recomputed day 1 on top of its own stored
# value, so its first day isn't reproducible from the inputs.
RSpec.describe "Golden tests against legacy WISP" do
  tolerance = 0.001

  dir = Pathname(ENV.fetch("GOLDEN_DIR", Rails.root.join("spec/fixtures/legacy").to_s))
  fixtures = dir.glob("*.json").sort

  if fixtures.empty?
    it "has fixtures to check" do
      skip "No legacy fixtures in #{dir}; see script/legacy/export_golden_fixtures.rb"
    end
  end

  fixtures.each do |path|
    describe path.basename(".json").to_s do
      fixture = JSON.parse(path.read, symbolize_names: true)
      days = fixture[:days].select { |day| day[:ad] }.map { |day| day.merge(date: Date.parse(day[:date])) }
      next if days.size < 2

      lai = fixture[:et_method] == "lai"
      end_date = fixture[:end_date] ? Date.parse(fixture[:end_date]) : Date.new(fixture[:year], 11, 30)
      emergence = Date.parse(fixture[:emergence_date])
      soil = fixture.slice(:field_capacity, :perm_wilting_pt, :max_root_zone_depth, :mad_frac)
      initial_ad, run_days = days.first[:ad], days.drop(1)
      expected = run_days.map { |day| day[:ad] }

      legacy_canopy = run_days.map { |day| lai ? day[:leaf_area_index] : (day[:entered_pct_cover] || day[:calculated_pct_cover]) }
      new_canopy = begin
        observations = lai ? [] : fixture[:days].filter_map { |d| [Date.parse(d[:date]), d[:entered_pct_cover]] if d[:entered_pct_cover] }
        curve = (lai && fixture[:plant] == "Field Corn") ? "field_corn" : nil
        canopy = Canopy.new(emergence_date: emergence, end_date:, observations:, curve:)
        run_days.map { |day| canopy.on(day[:date]) }
      end

      inputs = ->(canopies) do
        run_days.zip(canopies).map do |day, canopy|
          {date: day[:date], et0: day[:ref_et], rain: day[:rain], irrigation: day[:irrigation],
           moisture: day[:entered_pct_moisture], canopy:}
        end
      end
      legacy = ->(canopies, fixes) do
        LegacyEngine.run(**soil, days: inputs.call(canopies), et_method: fixture[:et_method], fixes:, initial_ad:)
      end

      it "is reproduced by LegacyEngine" do
        actual = legacy.call(legacy_canopy, [])
        mismatches = expected.each_index.reject { |i| (actual[i] - expected[i]).abs < tolerance }
        expect(mismatches).to be_empty,
          -> { "LegacyEngine differs from legacy on #{mismatches.size} days, first #{run_days[mismatches.first][:date]}" }
      end

      it "differs from legacy only where a listed fix explains it" do
        params = WaterBalance::Params.new(**soil, et_method: fixture[:et_method])
        new_days = run_days.zip(new_canopy).map do |day, canopy|
          WaterBalance::Day.new(date: day[:date], et0: day[:ref_et]&.positive? ? day[:ref_et] : nil, rain: day[:rain],
            irrigation: day[:irrigation], soil_moisture_pct: day[:entered_pct_moisture], canopy:)
        end
        actual = WaterBalance.run(params, new_days, initial_ad:).map(&:ad)

        all_fixes = LegacyEngine::FIXES.keys
        fixed = legacy.call(new_canopy, all_fixes)
        expect(actual.zip(fixed)).to all(satisfy { |a, b| (a - b).abs < tolerance })

        without = all_fixes.to_h { |fix| [fix, legacy.call(new_canopy, all_fixes - [fix])] }
        without[lai ? :c4 : :c3] = legacy.call(legacy_canopy, all_fixes)

        tally = Hash.new(0)
        unexplained = expected.each_index.select do |i|
          next false if (actual[i] - expected[i]).abs < tolerance
          causes = without.select { |_, ads| (ads[i] - fixed[i]).abs >= 1e-6 }.keys
          causes.each { |fix| tally[fix] += 1 }
          causes.empty?
        end

        differing = expected.each_index.count { |i| (actual[i] - expected[i]).abs >= tolerance }
        RSpec.configuration.reporter.message(
          "  #{path.basename(".json")}: #{differing}/#{expected.size} days differ" +
          (tally.any? ? " (#{tally.map { |fix, n| "#{fix.upcase} #{n}" }.join(", ")})" : "")
        )
        expect(unexplained).to be_empty,
          -> { "#{unexplained.size} differing days with no listed fix, first #{run_days[unexplained.first][:date]}" }
      end
    end
  end
end

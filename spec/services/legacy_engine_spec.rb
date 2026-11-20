require "rails_helper"

# Shows the port is faithful: legacy WISP with every listed fix applied is exactly WaterBalance,
# and without the fixes, every day that differs is explained by one of them.
RSpec.describe LegacyEngine do
  let(:rng) { Random.new(42) }
  let(:soil) { {field_capacity: 0.15, perm_wilting_pt: 0.05, max_root_zone_depth: 24.0, mad_frac: 0.5} }
  let(:late_start) { Date.new(2026, 7, 25) }
  let(:end_date) { Date.new(2026, 9, 20) }
  let(:evaporation) { {rew: 0.177, irrigation_fw: 1.0} }
  let(:crop) do
    {kc_mid: 1.15, crop_height_m: 0.6, kcb_mid: 1.10, kcb_end: 0.65, late_start:, end_date:, **evaporation}
  end
  let(:params) do
    WaterBalance::Params.new(**soil, **evaporation,
      crop: WaterBalance::Crop.new(kcb_mid: 1.10, kcb_end: 0.65, height_m: 0.6, late_start:, end_date:))
  end

  def season(length = 180)
    length.times.map do |i|
      {date: Date.new(2026, 4, 1) + i, et0: (rng.rand < 0.04) ? nil : rng.rand(0.0..0.35),
       rain: (rng.rand < 0.3) ? rng.rand(0.0..1.2) : 0.0, irrigation: (rng.rand < 0.1) ? 0.8 : 0.0,
       moisture: (rng.rand < 0.03) ? rng.rand(3.0..20.0) : nil, canopy: (i * 0.8).clamp(0, 100),
       wind_mph: (rng.rand < 0.05) ? nil : rng.rand(2.0..18.0), rh_min_pct: (rng.rand < 0.05) ? nil : rng.rand(15.0..95.0)}
    end
  end

  def new_engine(days)
    WaterBalance.run(params, days.map { |d|
      WaterBalance::Day.new(date: d[:date], et0: d[:et0], rain: d[:rain], irrigation: d[:irrigation],
        soil_moisture_pct: d[:moisture], canopy: d[:canopy], wind_mph: d[:wind_mph], rh_min_pct: d[:rh_min_pct])
    }).map(&:ad)
  end

  it "matches WaterBalance with every fix applied" do
    10.times do
      days = season
      legacy = described_class.run(**soil, **crop, days:, fixes: described_class::FIXES.keys)
      expect(new_engine(days).zip(legacy)).to all(satisfy { |new, old| (new - old).abs < 1e-4 })
    end
  end

  context "with drip irrigation (C22's wetted fraction)" do
    let(:evaporation) { {rew: 0.3, irrigation_fw: 0.35} }

    it "matches WaterBalance with every fix applied" do
      5.times do
        days = season
        legacy = described_class.run(**soil, **crop, days:, fixes: described_class::FIXES.keys)
        expect(new_engine(days).zip(legacy)).to all(satisfy { |new, old| (new - old).abs < 1e-4 })
      end
    end
  end

  context "by LAI" do
    let(:params) do
      WaterBalance::Params.new(**soil, **evaporation, et_method: "lai",
        crop: WaterBalance::Crop.new(kcb_mid: 1.10, kcb_end: 0.65, height_m: 0.6, late_start:, end_date:))
    end

    it "matches WaterBalance with every fix applied" do
      5.times do
        days = season.map { |day| day.merge(canopy: day[:canopy] / 20) }
        legacy = described_class.run(**soil, **crop, days:, et_method: "lai", fixes: described_class::FIXES.keys)
        expect(new_engine(days).zip(legacy)).to all(satisfy { |new, old| (new - old).abs < 1e-4 })
      end
    end
  end

  it "differs without the fixes only on days some fix explains" do
    differing = 0
    10.times do
      days = season
      all_fixes = described_class::FIXES.keys
      fixed = described_class.run(**soil, **crop, days:, fixes: all_fixes)
      unfixed = described_class.run(**soil, **crop, days:)
      without = all_fixes.to_h { |fix| [fix, described_class.run(**soil, **crop, days:, fixes: all_fixes - [fix])] }

      # A day at the wilting point (or field capacity) in the fixed run can be there with a fix removed
      # too, though the fix brought it there sooner: the differing day before it explains it
      bounds = [params.ad_pwp, params.ad_max]
      explained = false
      fixed.each_index do |i|
        next if (fixed[i] - unfixed[i]).abs < 1e-3
        differing += 1
        causes = without.select { |_, ads| (ads[i] - fixed[i]).abs >= 1e-6 }.keys
        held = bounds.any? { |bound| (fixed[i] - bound).abs < 1e-9 }
        explained = causes.any? || (held && explained)
        expect(explained).to be(true), "day #{i} differs by #{fixed[i] - unfixed[i]} with no fix to explain it"
      end
    end
    expect(differing).to be > 50 # the fixes do matter on these seasons
  end
end

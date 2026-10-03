require "rails_helper"

# Shows the port is faithful: legacy WISP with every listed fix applied is exactly WaterBalance,
# and without the fixes, every day that differs is explained by one of them.
RSpec.describe LegacyEngine do
  let(:rng) { Random.new(42) }
  let(:soil) { {field_capacity: 0.15, perm_wilting_pt: 0.05, max_root_zone_depth: 24.0, mad_frac: 0.5} }
  let(:params) { WaterBalance::Params.new(**soil) }

  def season(length = 180)
    length.times.map do |i|
      {date: Date.new(2026, 4, 1) + i, et0: (rng.rand < 0.04) ? nil : rng.rand(0.0..0.35),
       rain: (rng.rand < 0.3) ? rng.rand(0.0..1.2) : 0.0, irrigation: (rng.rand < 0.1) ? 0.8 : 0.0,
       moisture: (rng.rand < 0.03) ? rng.rand(3.0..20.0) : nil, canopy: (i * 0.8).clamp(0, 100)}
    end
  end

  def new_engine(days)
    WaterBalance.run(params, days.map { |d|
      WaterBalance::Day.new(date: d[:date], et0: d[:et0], rain: d[:rain], irrigation: d[:irrigation],
        soil_moisture_pct: d[:moisture], canopy: d[:canopy])
    }).map(&:ad)
  end

  it "matches WaterBalance with every fix applied" do
    10.times do
      days = season
      legacy = described_class.run(**soil, days:, fixes: described_class::FIXES.keys)
      expect(new_engine(days).zip(legacy)).to all(satisfy { |new, old| (new - old).abs < 1e-4 })
    end
  end

  it "differs without the fixes only on days some fix explains" do
    differing = 0
    10.times do
      days = season
      all_fixes = described_class::FIXES.keys
      fixed = described_class.run(**soil, days:, fixes: all_fixes)
      unfixed = described_class.run(**soil, days:)
      without = all_fixes.to_h { |fix| [fix, described_class.run(**soil, days:, fixes: all_fixes - [fix])] }

      fixed.each_index do |i|
        next if (fixed[i] - unfixed[i]).abs < 1e-3
        differing += 1
        causes = without.select { |_, ads| (ads[i] - fixed[i]).abs >= 1e-6 }.keys
        expect(causes).not_to be_empty, "day #{i} differs by #{fixed[i] - unfixed[i]} with no fix to explain it"
      end
    end
    expect(differing).to be > 50 # the fixes do matter on these seasons
  end
end

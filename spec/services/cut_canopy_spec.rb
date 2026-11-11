require "rails_helper"

# PLAN.md Phase 8 G.3: a perennial's cuttings restart its canopy, a sawtooth rather than one curve
RSpec.describe CutCanopy do
  let(:alfalfa) { create(:plant, key: "alfalfa", name: "Alfalfa") }
  let(:planting) do
    create(:planting, plant: alfalfa, season_start: Date.new(2026, 4, 1), emergence_date: Date.new(2026, 4, 15),
      end_date: Date.new(2026, 10, 15))
  end
  let(:canopy) { Canopy.for(planting.reload) }

  it "drops at each cutting and regrows on the perennial curve" do
    planting.canopy_cuttings.create!(date: Date.new(2026, 6, 1))
    planting.canopy_cuttings.create!(date: Date.new(2026, 7, 10))
    expect(canopy).to be_a(described_class)
    expect(canopy.on(Date.new(2026, 5, 31))).to be > 90 # full before the cut
    expect(canopy.on(Date.new(2026, 6, 1))).to be_within(0.1).of(5.0) # stubble
    expect(canopy.on(Date.new(2026, 6, 26))).to be_within(0.5).of(80) # 25 days on
    expect(canopy.on(Date.new(2026, 7, 9))).to be > 90
    expect(canopy.on(Date.new(2026, 7, 10))).to be_within(0.1).of(5.0)
    expect(canopy.on(Date.new(2026, 10, 16))).to eq(0.0) # after the season
  end

  it "fits each piece to its own readings only" do
    planting.canopy_cuttings.create!(date: Date.new(2026, 6, 1))
    planting.canopy_observations.create!(date: Date.new(2026, 5, 20), pct_cover: 60)
    expect(canopy.on(Date.new(2026, 5, 20))).to be_within(0.5).of(60)
    # The low reading before the cut leaves the regrowth alone
    expect(canopy.on(Date.new(2026, 6, 26))).to be_within(0.5).of(80)
  end

  it "only applies to the perennial curve, and stays a plain canopy without cuttings" do
    expect(canopy).to be_a(Canopy)
    potato = create(:planting, plant: create(:plant, key: "potato"))
    expect(potato.canopy_cuttings.build(date: potato.emergence_date + 30)).not_to be_valid
    expect(planting.canopy_cuttings.build(date: planting.emergence_date)).not_to be_valid
  end
end

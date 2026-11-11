require "rails_helper"

# PLAN.md Phase 8 G.3: crops without their own canopy curve follow a generic one, which readings
# correct; "none" is readings only, and until the first reading the planting needs canopy data.
RSpec.describe "Generic canopy curves" do
  let(:onion) { create(:plant, key: "onion", name: "Onion") }
  let(:pivot) { create(:pivot) }
  let(:field) { create(:field, pivot:) }
  let(:planting) do
    create(:planting, field:, plant: onion, season_start: Date.new(2026, 4, 1), emergence_date: Date.new(2026, 5, 1),
      end_date: Date.new(2026, 9, 30))
  end
  let(:today) { Date.new(2026, 7, 20) }
  let(:weather) { (Date.new(2026, 4, 1)..today).index_with { {et0: 0.2, precip: 0.0} } }

  def status = PlantingStatus.new(planting.reload, today:, weather:, ensemble: nil)

  it "reaches each generic curve's stated cover on its stated day" do
    {"leafy_fast" => [35, 80], "vegetable_medium" => [52, 80], "slow_partial" => [70, 55],
     "perennial_regrowth" => [25, 80]}.each do |key, (day, cover)|
      curve = CanopyCurve.generic.fetch(key)
      expect(curve.cover(Date.new(2026, 5, 1), Date.new(2026, 5, 1) + day)).to be_within(0.5).of(cover), key
    end
  end

  it "gives every crop without its own curve a generic default" do
    %w[onion alfalfa mint asparagus other garden_vegetables].each do |key|
      expect(CanopyCurve.for(key)).to be_nil
      expect(CanopyCurve.default_generic(key)).to be_present, key
    end
  end

  it "follows the generic default, so the crop uses water and gets a status" do
    expect(Canopy.for(planting).on(Date.new(2026, 7, 10))).to be_within(0.5).of(55) # slow, partial cover, day 70
    expect(status.status).to eq(:irrigate) # no rain or irrigation all season
    expect(status.days.last.result.adj_et).to be > 0.1
  end

  it "needs canopy data on readings only until the first reading" do
    planting.update!(canopy_curve_key: "none")
    expect(status).to have_attributes(status: :needs_canopy)
    expect(Outlook.for(status, depth: ->(d) { d.to_s }).headline).to eq("No canopy data")
    expect(status.tasks.find { |task| task.kind == :canopy }.due).to be(true)

    planting.canopy_observations.create!(date: Date.new(2026, 7, 10), pct_cover: 40)
    expect(status.status).not_to eq(:needs_canopy)
  end

  it "doesn't need canopy data before emergence" do
    planting.update!(canopy_curve_key: "none", emergence_date: Date.new(2026, 7, 25))
    expect(status.status).not_to eq(:needs_canopy)
  end
end

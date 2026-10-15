require "rails_helper"

RSpec.describe CanopyCurve do
  let(:emergence) { Date.new(2026, 5, 15) }

  def day_reaching(curve, pct) = (0..200).find { |day| curve.cover(emergence, emergence + day) >= pct }

  it "loads a curve, with its sources and confidence, for every crop listed" do
    expect(described_class.all.keys).to include("potato", "field_corn", "soybean", "snap_bean")
    expect(described_class.for("onion")).to be_nil
    described_class.all.each_value do |curve|
      expect(curve.sources).not_to be_empty
      expect(curve.confidence_label).to be_present
      covers = (0..200).map { |day| curve.cover(emergence, emergence + day) }
      expect(covers).to all(be_between(0.0, 100.0))
    end
  end

  it "reproduces the AquaCrop timings checked against Wisconsin 2026 (docs/canopy/02)" do
    {"potato" => [24, 31], "field_corn" => [29, 35], "snap_bean" => [31, 39], "soybean" => [40, 51]}.each do |key, (d50, d80)|
      curve = described_class.for(key)
      expect([day_reaching(curve, 50), day_reaching(curve, 80)]).to eq([d50, d80]), key
    end
  end

  it "is 0 before emergence" do
    expect(described_class.for("potato").cover(emergence, emergence - 1)).to eq(0.0)
  end

  it "declines potato from August 1 by 10 points a week to 50%" do
    potato = described_class.for("potato")
    expect(potato.cover(emergence, Date.new(2026, 8, 1))).to be_within(0.01).of(92)
    expect(potato.cover(emergence, Date.new(2026, 8, 15))).to be_within(0.01).of(72)
    expect(potato.cover(emergence, Date.new(2026, 9, 15))).to eq(50.0)
  end

  it "starts potato's decline once the canopy is full, for a late planting" do
    potato = described_class.for("potato")
    late = Date.new(2026, 7, 1)
    full = late + potato.full_day
    expect(full).to be > Date.new(2026, 8, 1)
    expect(potato.cover(late, full)).to be >= 0.98 * 92
    expect(potato.cover(late, full + 7)).to be_within(0.01).of(92 - 10)
  end

  it "declines by AquaCrop's equation from its start day" do
    corn = described_class.for("field_corn")
    expect(corn.cover(emergence, emergence + 101)).to be_within(0.1).of(96)
    expect(corn.cover(emergence, emergence + 115)).to be < 80
  end
end

require "rails_helper"

RSpec.describe CanopyFit do
  let(:potato) { CanopyCurve.for("potato") }
  let(:emergence) { Date.new(2026, 5, 15) }
  let(:curve) { ->(**fit) { potato.from(emergence, **fit) } }

  def fit(readings) = described_class.run(readings, curve:, noise: CanopyFit::COVER_NOISE, censor_at: CanopyFit::COVER_CENSOR)

  # Readings from a crop running `ahead` days ahead of the typical curve, on the given days after emergence
  def ahead_by(ahead, days) = days.map { |day| [emergence + day, potato.cover(emergence, emergence + day + ahead)] }

  it "keeps a fit until its readings change" do
    readings = ahead_by(6, [10, 14, 18])
    expected = fit(readings)
    expect(described_class).to receive(:run).twice.and_call_original
    fetch = ->(readings) { described_class.fetch(["cover", "potato", emergence], readings, curve:, noise: 10.0, censor_at: 80.0) }
    expect([fetch.call(readings), fetch.call(readings)]).to eq([expected, expected])
    fetch.call(readings + ahead_by(6, [22])) # a new reading: fitted again
  end

  it "leaves the curve as it is without readings, or with readings on it" do
    expect(fit([])).to be_typical
    expect(fit(ahead_by(0, [14, 21, 28]))).to be_typical
  end

  it "moves little for one reading, and most of the way as consistent readings add up" do
    one = fit(ahead_by(6, [20]))
    several = fit(ahead_by(6, [10, 14, 18, 22, 26, 30]))
    expect(one.shift).to be_between(-3, 0)
    expect(several.shift).to be_between(-6, -4)
    expect([several.stretch, several.height]).to all(be_within(0.11).of(1.0))
  end

  it "fits a slower crop by stretching the curve, held back toward the typical one" do
    slow = (10..40).step(5).map { |day| [emergence + day, potato.cover(emergence, emergence + day, stretch: 1.3)] }
    expect(fit(slow).stretch).to be_between(1.1, 1.3)
  end

  it "takes readings of 80% or more as at least 80, so held readings don't pull the canopy down" do
    held = [28, 35, 42, 49].map { |day| [emergence + day, 80.0] } # the curve is 85–92% then
    expect(fit(held).height).to be >= 1.0
  end

  it "stays within its grid however far off the readings are" do
    wild = fit([[emergence + 5, 90.0], [emergence + 6, 95.0]])
    expect(wild.shift).to eq(-CanopyFit::MAX_SHIFT)
    expect(wild.height).to be <= Math.exp(CanopyFit::HEIGHT_STEPS * CanopyFit::STEP)
  end
end

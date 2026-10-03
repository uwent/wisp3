require "rails_helper"

RSpec.describe Canopy do
  let(:emergence) { Date.new(2026, 5, 15) }
  let(:end_date) { Date.new(2026, 9, 30) }

  def canopy(observations = [], curve: nil)
    described_class.new(emergence_date: emergence, end_date:, observations:, curve:)
  end

  it "is 0 everywhere with no readings and no curve" do
    expect(canopy.on(Date.new(2026, 7, 1))).to eq(0.0)
  end

  it "rises from 0 at emergence to the first reading" do
    c = canopy([[Date.new(2026, 5, 25), 20.0]])
    expect(c.on(emergence - 1)).to eq(0.0)
    expect(c.on(emergence)).to eq(0.0)
    expect(c.on(Date.new(2026, 5, 20))).to be_within(1e-9).of(10.0)
    expect(c.on(Date.new(2026, 5, 25))).to eq(20.0)
  end

  it "interpolates between readings, in any order given" do
    c = canopy([[Date.new(2026, 6, 20), 60.0], [Date.new(2026, 6, 10), 40.0]])
    expect(c.on(Date.new(2026, 6, 15))).to be_within(1e-9).of(50.0)
  end

  it "holds the last reading until the end date, then drops to 0 (C3)" do
    c = canopy([[Date.new(2026, 6, 10), 80.0]])
    expect(c.on(Date.new(2026, 6, 17))).to eq(80.0) # legacy: back to 0 after 6 days
    expect(c.on(end_date)).to eq(80.0)
    expect(c.on(end_date + 1)).to eq(0.0)
  end

  it "takes a reading on the emergence date as is" do
    expect(canopy([[emergence, 5.0]]).on(emergence)).to eq(5.0)
  end

  it "ignores readings before emergence" do
    c = canopy([[emergence - 5, 30.0], [Date.new(2026, 5, 25), 20.0]])
    expect(c.on(emergence - 5)).to eq(0.0)
    expect(c.on(Date.new(2026, 5, 20))).to be_within(1e-9).of(10.0)
  end

  describe "the field corn LAI curve (WIS v6.3.11)" do
    let(:corn) { canopy(curve: "field_corn") }

    it "matches the spreadsheet's values by day since emergence" do
      {30 => 0.25, 50 => 1.95, 80 => 4.07, 100 => 3.25, 140 => 0.86}.each do |day, lai|
        expect(CanopyModel.lai("field_corn", day)).to be_within(0.01).of(lai)
      end
    end

    it "is used when there are no readings, from emergence" do
      expect(corn.on(emergence - 1)).to eq(0.0)
      expect(corn.on(emergence + 80)).to be_within(0.01).of(4.07)
    end

    it "is replaced by readings when there are some" do
      c = canopy([[Date.new(2026, 7, 1), 3.0]], curve: "field_corn")
      expect(c.on(Date.new(2026, 8, 15))).to eq(3.0)
    end
  end
end

require "rails_helper"

RSpec.describe Weather::DegreeDays do
  it "caps at 86 °F and floors at 50 °F (modified GDD, base 50)" do
    expect(described_class.daily(80, 60)).to eq(20.0)
    expect(described_class.daily(95, 70)).to eq(28.0) # max capped at 86
    expect(described_class.daily(70, 40)).to eq(10.0) # min floored at 50
    expect(described_class.daily(45, 30)).to eq(0.0)
    expect(described_class.daily(nil, 30)).to be_nil
  end

  it "accumulates in date order, carrying over missing days" do
    days = {Date.new(2026, 6, 2) => [nil, nil], Date.new(2026, 6, 1) => [80, 60], Date.new(2026, 6, 3) => [70, 50]}
    expect(described_class.cumulative(days).values).to eq([20.0, 20.0, 30.0])
  end
end

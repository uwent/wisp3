require "rails_helper"

RSpec.describe WeatherPanel do
  let(:cell) { WeatherCell.for(44.12, -89.53) }

  before do
    (Date.new(2026, 7, 1)..Date.new(2026, 7, 3)).each do |date|
      cell.weather_days.create!(date:, tmax_f: 80, tmin_f: 60, soil_moisture_0_7cm: 0.123456, model: "m", hours: 24,
        fetched_at: Time.current)
    end
    cell.weather_forecasts.create!(issued_at: 1.hour.ago, model: "m", payload: {days: [
      {date: "2026-07-03", tmax_f: 99, tmin_f: 99}, # stored already: the stored day wins
      {date: "2026-07-04", tmax_f: 90, tmin_f: 70},
      {date: "2026-07-20", tmax_f: 90, tmin_f: 70} # outside the range
    ]})
  end

  it "joins stored days and the forecast after them, with GDD since emergence" do
    days = described_class.new(cell, Date.new(2026, 7, 1)..Date.new(2026, 7, 10), emergence_date: Date.new(2026, 7, 2)).days
    expect(days.map { |day| [day.date.day, day.forecast, day.gdd, day.gdd_since_emergence] })
      .to eq([[1, false, 20.0, 0.0], [2, false, 20.0, 20.0], [3, false, 20.0, 40.0], [4, true, 28.0, 68.0]]) # the high is capped at 86 °F
    expect(days.first.soil_moisture_0_7cm).to eq(0.123)
  end

  it "is empty without a cell" do
    expect(described_class.new(nil, Date.new(2026, 7, 1)..Date.new(2026, 7, 2), emergence_date: Date.new(2026, 7, 1)).days).to eq([])
  end
end

require "rails_helper"

RSpec.describe ForecastDays do
  let(:cell) { create(:pivot).weather_cell }
  let(:today) { Date.new(2026, 7, 20) }
  let(:dates) { (today - 2..today + 9).to_a }

  before do
    cell.weather_forecasts.create!(issued_at: 2.hours.ago, model: "ncep_nbm_conus", payload: {days: dates.map do |date|
      {date: date.iso8601, tmax_f: 85.123456, tmin_f: 60, precip_in: (date == today) ? 0.3 : 0.0, weather_code: (date == today) ? 63 : 1}
    end})
  end

  it "gives the week from today from the latest forecast, values as stored" do
    days = described_class.for(cell, today:)
    expect(days.map(&:date)).to eq((today..today + 6).to_a)
    expect(days.first).to have_attributes(tmax_f: 85.123, tmin_f: 60, precip_in: 0.3, weather_code: 63, et0_in: nil,
      precip_chance: nil)
  end

  it "takes the chance of precipitation from the ensemble's members" do
    cell.weather_forecasts.create!(kind: "ensemble", issued_at: 1.hour.ago, model: "gfs_seamless", payload: {
      dates: [today.iso8601, (today + 1).iso8601],
      members: [{et0_in: [0.2, 0.2], precip_in: [0.5, 0.0]}, {et0_in: [0.2, 0.2], precip_in: [0.0, 0.0]},
        {et0_in: [0.2, 0.2], precip_in: [0.02, nil]}, {et0_in: [0.2, 0.2], precip_in: [0.005, nil]}]
    })
    days = described_class.for(cell, today:)
    expect(days.first(3).map(&:precip_chance)).to eq([50, 0, nil])
  end

  it "is empty without a forecast or a cell" do
    expect(described_class.by_cell([create(:pivot, latitude: 45.5).weather_cell_id], today:).values).to eq([[]])
    expect(described_class.for(nil, today:)).to eq([])
  end
end

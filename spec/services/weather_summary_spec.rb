require "rails_helper"

RSpec.describe WeatherSummary do
  let(:cell) { create(:pivot).weather_cell }
  let(:today) { Date.new(2026, 7, 20) }

  def store(date, **values)
    cell.weather_days.create!(date:, model: "ncep_nbm_conus", hours: 24, fetched_at: Time.current, **values)
  end

  it "totals the last week's stored days and the next week of the latest forecast" do
    store(today - 8, precip_in: 5.0, et0_in: 5.0, tmax_f: 100, tmin_f: 0) # before the week
    store(today - 2, precip_in: 0.5, et0_in: 0.2, tmax_f: 80, tmin_f: 55)
    store(today - 1, precip_in: 0.0, et0_in: 0.25, tmax_f: 84, tmin_f: 61)
    cell.weather_forecasts.create!(issued_at: 1.day.ago, model: "ncep_nbm_conus", payload: {days: []})
    days = (today - 1..today + 8).map { |date| {date: date.iso8601, precip_in: 0.1, et0_in: 0.2, tmax_f: 70 + date.day % 5, tmin_f: 50} }
    cell.weather_forecasts.create!(issued_at: Time.current, model: "ncep_nbm_conus", payload: {days:})

    summary = described_class.by_cell([cell.id], today:).fetch(cell.id)
    expect(summary[:past]).to have_attributes(days: 2, precip: 0.5, et0: 0.45, tmax: 80.0..84.0, tmin: 55.0..61.0)
    expect(summary[:ahead]).to have_attributes(days: 7, precip: be_within(1e-9).of(0.7), et0: be_within(1e-9).of(1.4),
      tmax: 70..74, tmin: 50..50)
  end

  it "leaves out what's missing rather than counting it as zero" do
    store(today - 1, precip_in: nil, et0_in: 0.2)
    summary = described_class.by_cell([cell.id], today:).fetch(cell.id)
    expect(summary[:past]).to have_attributes(days: 1, precip: nil, et0: 0.2, tmax: nil)
    expect(summary[:ahead]).to be_nil
  end
end

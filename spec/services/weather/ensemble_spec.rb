require "rails_helper"

RSpec.describe Weather::Ensemble do
  def response(times, values)
    Weather::OpenMeteo::Hourly.new(latitude: 44, longitude: -89, timezone: "America/Chicago", elevation: 300, times:, values:)
  end

  let(:times) { %w[2026-07-19 2026-07-20 2026-07-21].flat_map { |d| (0..23).map { |h| format("%sT%02d:00", d, h) } } }

  it "sums each member's hours into daily inches from today on, the control first" do
    hourly = {
      "et0_fao_evapotranspiration" => Array.new(72, 0.2), "precipitation" => Array.new(72, 0.0),
      "et0_fao_evapotranspiration_member01" => Array.new(72, 0.3), "precipitation_member01" => Array.new(48, 0.0) + Array.new(24, 1.0),
      "et0_fao_evapotranspiration_member02" => Array.new(72, 0.1), "precipitation_member02" => Array.new(72, 0.5)
    }
    payload = described_class.from_hourly(response(times, hourly), today: Date.new(2026, 7, 20))
    expect(payload["dates"]).to eq(%w[2026-07-20 2026-07-21])
    expect(payload["members"].size).to eq(3)
    expect(payload["members"][0]).to eq("et0_in" => [0.189, 0.189], "precip_in" => [0.0, 0.0])
    expect(payload["members"][1]["precip_in"]).to eq([0.0, 0.9449])
    expect(payload["members"][2]["et0_in"]).to eq([0.0945, 0.0945])
  end

  it "leaves a member's day out when too many hours are missing" do
    hourly = {"et0_fao_evapotranspiration" => Array.new(48, 0.2) + [0.2] * 20 + [nil] * 4, "precipitation" => Array.new(72, 0.0)}
    payload = described_class.from_hourly(response(times, hourly), today: Date.new(2026, 7, 20))
    expect(payload["members"].sole["et0_in"]).to eq([0.189, nil])
  end

  it "reads back as each member's balance inputs by date" do
    cell = WeatherCell.create!(latitude: 44, longitude: -89)
    forecast = cell.weather_forecasts.create!(kind: "ensemble", issued_at: Time.current, model: "gfs_seamless",
      payload: {"dates" => %w[2026-07-20], "members" => [{"et0_in" => [0.2], "precip_in" => [0.1]}]})
    expect(forecast.members).to eq([{Date.new(2026, 7, 20) => {et0: 0.2, precip: 0.1}}])
    expect(cell.latest_ensemble).to eq(forecast)
    expect(cell.latest_forecast).to be_nil
  end
end

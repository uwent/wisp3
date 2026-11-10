require "rails_helper"

RSpec.describe Weather::Ensemble do
  def response(times, values)
    Weather::OpenMeteo::Hourly.new(latitude: 44, longitude: -89, timezone: "America/Chicago", elevation: 300, times:, values:)
  end

  let(:times) { (0...72).map { |h| Time.utc(2026, 7, 19, 5) + h * 3600 } } # local days, Chicago

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

  describe ".corrected" do
    let(:payload) do
      {"dates" => %w[2026-07-20 2026-07-21 2026-07-22],
       "members" => [{"et0_in" => [0.2, 0.2, nil], "precip_in" => [0.0, 0.1, 0.0]}, {"et0_in" => [0.1, 0.3, 0.2], "precip_in" => [0, 0, 0]}]}
    end

    def forecast(days) = WeatherForecast.new(payload: {"days" => days})

    it "scales each member's ET0 by the deterministic forecast's corrected/raw ratio for the day, keeping the ratios" do
      out = described_class.corrected(payload, forecast([
        {"date" => "2026-07-20", "et0_in" => 0.18, "et0_openmeteo_in" => 0.2},
        {"date" => "2026-07-21", "et0_in" => 0.16, "et0_openmeteo_in" => 0.2},
        {"date" => "2026-07-22", "et0_in" => 0.0, "et0_openmeteo_in" => 0.005} # too small for a ratio: the mean
      ]))
      expect(out["et0_ratio"]).to eq [0.9, 0.8, 0.85]
      expect(out["members"].map { |m| m["et0_in"] }).to eq [[0.18, 0.16, nil], [0.09, 0.24, 0.17]]
      expect(out["members"].first["precip_in"]).to eq [0.0, 0.1, 0.0]
      expect(out["corrections"]).to eq ["et0-ensemble-ratio v1"]
    end

    it "leaves the payload alone without a corrected forecast" do
      expect(described_class.corrected(payload, nil)).to eq payload
      expect(described_class.corrected(payload, forecast([{"date" => "2026-07-20", "et0_in" => 0.18}]))).to eq payload
    end
  end
end

require "rails_helper"

RSpec.describe Weather::Daily do
  def hourly(times, values) = Weather::OpenMeteo::Hourly.new(latitude: 44, longitude: -89, timezone: "America/Chicago",
    elevation: 300, times:, values:)

  let(:times) { (0..23).map { |h| format("2026-07-01T%02d:00", h) } + ["2026-07-02T00:00"] }

  it "sums, averages and takes extremes by local day, converting to inches and °F" do
    days = described_class.from_hourly(hourly(times, {
      "et0_fao_evapotranspiration" => [0.254] * 24 + [0.0],
      "precipitation" => [0.0] * 23 + [25.4, 1.0],
      "temperature_2m" => (0..23).map { |h| 10.0 + h } + [5.0],
      "snow_depth" => [0.01] * 25
    }))
    day = days[Date.new(2026, 7, 1)]
    expect(day["hours"]).to eq(24)
    expect(day["et0_in"]).to be_within(1e-9).of(0.24)
    expect(day["precip_in"]).to be_within(1e-9).of(1.0)
    expect(day["tmax_f"]).to be_within(1e-9).of(91.4) # 33 °C
    expect(day["tmin_f"]).to be_within(1e-9).of(50.0)
    expect(day["snow_depth_in"]).to be_within(1e-9).of(10 / 25.4)
    expect(days[Date.new(2026, 7, 2)]["hours"]).to eq(1)
  end

  it "leaves a value missing when more than 2 of its hours are missing, and when the model has none" do
    days = described_class.from_hourly(hourly(times.first(24), {
      "et0_fao_evapotranspiration" => [0.2] * 21 + [nil] * 3,
      "precipitation" => [0.0] * 22 + [nil] * 2,
      "soil_moisture_0_to_7cm" => [nil] * 24
    }))
    day = days[Date.new(2026, 7, 1)]
    expect(day["et0_in"]).to be_nil
    expect(day["precip_in"]).to eq(0.0)
    expect(day["soil_moisture_0_7cm"]).to be_nil
  end

  it "merges the soil model's values into the primary model's days" do
    primary = hourly(times.first(24), {"temperature_2m" => [20.0] * 24})
    soil = hourly(times.first(24), {"soil_moisture_0_to_7cm" => [0.25] * 24, "soil_temperature_0_to_7cm" => [15.0] * 24})
    day = described_class.from_hourly(primary, soil)[Date.new(2026, 7, 1)]
    expect(day).to include("tmean_f" => 68.0, "soil_moisture_0_7cm" => 0.25, "soil_temp_0_7cm_f" => 59.0)
  end

  it "averages wind directions as vectors" do
    expect(described_class.mean_direction([350, 10])).to be_within(1e-9).of(0.0).or be_within(1e-9).of(360.0)
    expect(described_class.mean_direction([80, 100])).to be_within(1e-9).of(90.0)
  end

  it "handles the 23-hour day when clocks spring forward" do
    spring = (0..23).reject { |h| h == 2 }.map { |h| format("2026-03-08T%02d:00", h) }
    day = described_class.from_hourly(hourly(spring, {"precipitation" => [1.0] * 23}))[Date.new(2026, 3, 8)]
    expect(day["hours"]).to eq(23)
    expect(day["precip_in"]).to be_within(1e-9).of(23 / 25.4)
  end
end

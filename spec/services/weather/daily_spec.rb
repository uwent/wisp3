require "rails_helper"

RSpec.describe Weather::Daily do
  def hourly(times, values) = Weather::OpenMeteo::Hourly.new(latitude: 44, longitude: -89, timezone: "America/Chicago",
    elevation: 300, times:, values:)

  def from_hourly(*responses) = described_class.from_hourly(*responses, latitude: 44.0, longitude: -89.0)

  # Hours stamped local midnight July 1 through midnight July 2 (CDT, UTC−5), as UTC
  let(:times) { (0..24).map { |h| Time.utc(2026, 7, 1, 5) + h * 3600 } }

  it "sums, averages and takes extremes by local day, converting to inches and °F" do
    days = from_hourly(hourly(times, {
      "et0_fao_evapotranspiration" => [0.254] * 24 + [0.0],
      "precipitation" => [0.0] * 23 + [25.4, 1.0],
      "temperature_2m" => (0..23).map { |h| 10.0 + h } + [5.0],
      "snow_depth" => [0.01] * 25
    }))
    day = days[Date.new(2026, 7, 1)]
    expect(day["hours"]).to eq(24)
    expect(day["et0_openmeteo_in"]).to be_within(1e-9).of(0.24)
    expect(day["precip_in"]).to be_within(1e-9).of(1.0)
    expect(day["tmax_f"]).to be_within(1e-9).of(91.4) # 33 °C
    expect(day["tmin_f"]).to be_within(1e-9).of(50.0)
    expect(day["snow_depth_in"]).to be_within(1e-9).of(10 / 25.4)
    expect(days[Date.new(2026, 7, 2)]["hours"]).to eq(1)
  end

  it "leaves a value missing when more than 2 of its hours are missing, and when the model has none" do
    days = from_hourly(hourly(times.first(24), {
      "et0_fao_evapotranspiration" => [0.2] * 21 + [nil] * 3,
      "precipitation" => [0.0] * 22 + [nil] * 2,
      "soil_moisture_0_to_7cm" => [nil] * 24
    }))
    day = days[Date.new(2026, 7, 1)]
    expect(day["et0_openmeteo_in"]).to be_nil
    expect(day["precip_in"]).to eq(0.0)
    expect(day["soil_moisture_0_7cm"]).to be_nil
    expect(day["et0_in"]).to be_nil # no inputs for WISP's own
    expect(day["corrections"]).to eq []
  end

  it "merges the soil model's values into the primary model's days" do
    primary = hourly(times.first(24), {"temperature_2m" => [20.0] * 24})
    soil = hourly(times.first(24), {"soil_moisture_0_to_7cm" => [0.25] * 24, "soil_temperature_0_to_7cm" => [15.0] * 24})
    day = from_hourly(primary, soil)[Date.new(2026, 7, 1)]
    expect(day).to include("tmean_f" => 68.0, "soil_moisture_0_7cm" => 0.25, "soil_temp_0_7cm_f" => 59.0)
  end

  it "takes each hour of each variable from the first model that has it (NBM, then best_match)" do
    nbm = hourly(times.first(24), {"precipitation" => [1.0] * 20 + [nil] * 4, "cloud_cover" => [nil] * 24})
    best_match = hourly(times.first(24), {"precipitation" => [2.0] * 24, "cloud_cover" => [40.0] * 24})
    day = from_hourly(nbm, best_match)[Date.new(2026, 7, 1)]
    expect(day["precip_in"]).to be_within(1e-9).of(28 / 25.4)
    expect(day["cloud_cover_pct"]).to eq(40.0)
  end

  it "corrects shortwave and humidity and computes ET0 from the corrected hours, keeping the raw values" do
    sun = times.first(24).map { |t| [800 * Math.sin(Weather::Fao56.radians([Weather::Fao56.solar_elevation_deg(t - 1800, 44, -89), 0].max)), 0].max }
    day = from_hourly(hourly(times.first(24), {
      "temperature_2m" => [22.0] * 24, "dew_point_2m" => [16.0] * 24, "wind_speed_10m" => [10.0] * 24,
      "surface_pressure" => [980.0] * 24, "shortwave_radiation" => sun, "et0_fao_evapotranspiration" => [0.25] * 24
    }))[Date.new(2026, 7, 1)]
    expect(day["shortwave_raw_mj"]).to be_within(1e-9).of(sun.sum * 0.0036)
    expect(day["shortwave_mj"]).to be < day["shortwave_raw_mj"]
    expect(day["dew_point_raw_f"]).to be_within(1e-9).of(60.8)
    expect(day["rh_mean_raw_pct"]).to be_within(0.1).of(68.8)
    expect(day["rh_mean_pct"]).not_to eq(day["rh_mean_raw_pct"])
    expect(day["et0_in"]).to be_between(0.12, 0.25)
    expect(day["et0_openmeteo_in"]).to be_within(1e-9).of(6 / 25.4)
    expect(day["corrections"]).to eq ["openmeteo-shortwave v1", "openmeteo-rh v1", "et0-fao56 v1"]
  end

  it "averages wind directions as vectors" do
    expect(described_class.mean_direction([350, 10])).to be_within(1e-9).of(0.0).or be_within(1e-9).of(360.0)
    expect(described_class.mean_direction([80, 100])).to be_within(1e-9).of(90.0)
  end

  it "handles the 23-hour day when clocks spring forward" do
    spring = (0...23).map { |h| Time.utc(2026, 3, 8, 6) + h * 3600 } # local midnight CST to 11 pm CDT
    day = from_hourly(hourly(spring, {"precipitation" => [1.0] * 23}))[Date.new(2026, 3, 8)]
    expect(day["hours"]).to eq(23)
    expect(day["precip_in"]).to be_within(1e-9).of(23 / 25.4)
  end
end

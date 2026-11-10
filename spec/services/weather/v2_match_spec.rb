require "rails_helper"

# WISP's corrected hours against AgWeather v2's for the same Open-Meteo responses (PLAN.md Phase 8 E,
# step 6): three June 2025 days at the O1280 cell over Stillwater, OK, NBM then best_match. v2's values
# come from docs/weather-corrections/v2_expected.py; rerun it when a table or the method changes.
RSpec.describe "Weather corrections against AgWeather v2" do
  let(:expected) { JSON.parse(file_fixture("weather_corrections/v2_expected.json").read) }

  # v2 asks for wind in m/s; WISP takes Open-Meteo's default km/h
  def response(model)
    json = JSON.parse(file_fixture("weather_corrections/openmeteo_historical_#{model}.json").read)
    hourly = json.fetch("hourly")
    values = hourly.except("time").to_h do |name, series|
      [name, name.start_with?("wind_speed", "wind_gusts") ? series.map { |s| s && s * 3.6 } : series]
    end
    Weather::OpenMeteo::Hourly.new(latitude: json["latitude"], longitude: json["longitude"], timezone: "Etc/UTC",
      elevation: json["elevation"], times: hourly.fetch("time").map { |s| Time.at(s).utc }, values:)
  end

  let(:hours) do
    Weather::Hours.merge(response("ncep_nbm_conus"), response("best_match"))
      .corrected(latitude: expected["latitude"], longitude: expected["longitude"])
  end

  def expect_hours(actual, wanted, label, &close)
    expect(actual.size).to eq(wanted.size)
    actual.zip(wanted).each_with_index do |(a, w), k|
      if w.nil?
        expect(a).to be_nil, "#{label} at hour #{k}: expected nil, got #{a}"
      else
        expect(a).not_to be_nil, "#{label} at hour #{k}: expected #{w}, got nil"
        expect(close.call(a, w)).to be(true), "#{label} at hour #{k}: expected #{w}, got #{a}"
      end
    end
  end

  it "is on v2's cell" do
    cell = Weather::Grid.cell_for(36.12, -97.07)
    expect(cell.latitude).to be_within(1e-9).of(expected["latitude"])
    expect(cell.longitude).to be_within(1e-9).of(expected["longitude"])
  end

  it "merges the same hours from the two models" do
    expect(hours.times.map(&:to_i)).to eq expected["hour_end"]
    expect_hours(hours.series("temperature_2m"), expected["temperature_c"], "temperature") { |a, w| (a - w).abs < 1e-9 }
    expect_hours(hours.series("surface_pressure").map { |p| p && p / 10 }, expected["pressure_kpa"], "pressure") { |a, w| (a - w).abs < 1e-9 }
  end

  it "corrects shortwave within 0.1%" do
    expect_hours(hours.values["shortwave_radiation_raw"], expected["shortwave_raw_w_m2"], "raw shortwave") { |a, w| (a - w).abs < 1e-9 }
    expect_hours(hours.values["shortwave_radiation"], expected["shortwave_w_m2"], "shortwave") { |a, w| (a - w).abs <= [w.abs * 1e-3, 1e-6].max }
  end

  it "corrects the dew point and RH within 0.1 point" do
    expect_hours(hours.values["dew_point_2m"], expected["dew_point_c"], "dew point") { |a, w| (a - w).abs < 0.01 }
    expect_hours(hours.values["relative_humidity"], expected["relative_humidity_percent"], "RH") { |a, w| (a - w).abs < 0.1 }
  end

  it "computes ET0 within 0.1% (or 0.001 mm at night)" do
    expect_hours(hours.values["et0"], expected["et0_mm"], "ET0") { |a, w| (a - w).abs <= [w.abs * 1e-3, 1e-3].max }
    expect(hours.values["et0"].compact.sum).to be_within(0.005).of(expected["et0_mm"].compact.sum)
  end
end

require "rails_helper"

RSpec.describe Weather::Corrections do
  subject(:corrections) { described_class }

  # Madison, a clear July noon (hour ending 18:00 UTC) and midnight
  let(:noon) { Time.utc(2026, 7, 15, 18) }
  let(:midnight) { Time.utc(2026, 7, 15, 6) }

  it "lists each correction with its version and fitted date from its table" do
    expect(corrections.all.map(&:label)).to eq ["openmeteo-shortwave v1", "openmeteo-rh v1", "et0-fao56 v1"]
    shortwave = corrections.find("openmeteo-shortwave")
    expect(shortwave.fitted).to eq "2026-10-31"
    expect(shortwave.source).to include "Wisconet"
    expect(corrections.all).to all(have_attributes(method: be_present, evidence: start_with("https://")))
  end

  describe ".shortwave" do
    def correct(values, times: [noon] * values.size, pressure: [98.0] * values.size)
      corrections.shortwave(hour_ends: times, latitude: 43.07, longitude: -89.40, shortwave_w_m2: values, pressure_kpa: pressure)
    end

    it "scales a clear hour by the clear bins' factor and a dark hour's 0 stays 0" do
      rso = Weather::Fao56.clear_sky_shortwave_w_m2(noon, 43.07, -89.40, 98.0)
      clear = correct([0.95 * rso]).first
      expect(clear / (0.95 * rso)).to be_within(1e-9).of(0.9026)
      expect(correct([0.0], times: [midnight])).to eq [0.0]
      expect(correct([5.0], times: [midnight]).first).to be_within(1e-9).of(5 * 0.6171) # twilight: the darkest bin
    end

    it "leaves missing hours missing and falls back to 97 kPa without pressure" do
      expect(correct([nil])).to eq [nil]
      expect(correct([500.0], pressure: [nil]).first).to be_within(1e-9).of(correct([500.0], pressure: [97.0]).first)
    end
  end

  describe ".dew_point" do
    it "keeps the temperature as the ceiling and missing inputs missing" do
      out = corrections.dew_point(hour_ends: [midnight, noon, noon], longitude: -89.40,
        temperature_c: [18.0, 30.0, nil], dew_point_c: [17.5, 12.0, 10.0])
      expect(out[0]).to be <= 18.0
      expect(out[1]).to be < 30.0
      expect(out[2]).to be_nil
    end

    it "moves a humid night toward saturation, as the map was fitted to (Open-Meteo runs dry)" do
      t, td = 15.0, 13.5
      mapped = corrections.dew_point(hour_ends: [midnight], longitude: -89.40, temperature_c: [t], dew_point_c: [td]).first
      expect(Weather::Fao56.relative_humidity_percent(t, mapped)).to be > Weather::Fao56.relative_humidity_percent(t, td)
    end
  end

  it "blends seasons around the year's end" do
    expect(corrections.season_neighbours(300, [15, 105, 196, 288])).to eq [[3, 1 - 12 / 92.0], [0, 12 / 92.0]]
    expect(corrections.season_neighbours(5, [15, 105, 196, 288])).to eq [[3, 1 - 82 / 92.0], [0, 82 / 92.0]]
  end
end

require "rails_helper"

# Ported from AgWeather v2's packages/agmodels/tests/test_weather.py (at bbb0a6d)
RSpec.describe Weather::Fao56 do
  subject(:fao) { described_class }

  # FAO-56 Example 19: N'Diaye, Senegal (16°13'N, 16°15'W, 8 m), 1 October. Its clock uses a 15°W
  # standard meridian, so clock time is UTC − 1 h: its 14–15 h is the hour ending 16:00 UTC.
  let(:lat) { 16 + 13 / 60.0 }
  let(:lon) { -(16 + 15 / 60.0) }
  let(:z) { 8 }
  let(:day_end) { Time.utc(2026, 10, 1, 16) }
  let(:night_end) { Time.utc(2026, 10, 1, 4) }
  let(:pressure) { fao.pressure_at_elevation_kpa(z) } # 101.2 kPa

  it "matches Example 19's humidity terms" do
    expect(fao.saturation_vapor_pressure_kpa(38)).to be_within(0.001).of(6.625)
    expect(fao.svp_slope_kpa_per_c(38)).to be_within(0.001).of(0.358)
    expect(fao.psychrometric_constant_kpa_per_c(pressure)).to be_within(0.0001).of(0.0673)
    expect(fao.saturation_vapor_pressure_kpa(28)).to be_within(0.001).of(3.780)
  end

  it "matches Examples 2–5's humidity terms" do
    # Example 3: Tmax 24.5 and Tmin 15 °C give e° 3.075 and 1.705, so es 2.39 kPa
    expect(fao.saturation_vapor_pressure_kpa(24.5)).to be_within(0.001).of(3.075)
    expect(fao.saturation_vapor_pressure_kpa(15)).to be_within(0.001).of(1.705)
    es = (fao.saturation_vapor_pressure_kpa(24.5) + fao.saturation_vapor_pressure_kpa(15)) / 2
    expect(es).to be_within(0.001).of(2.39)
    # Example 4: the slope at 16.9 °C
    expect(fao.svp_slope_kpa_per_c(16.9)).to be_within(0.001).of(0.122)
    # Example 2: at 1800 m, 81.8 kPa and γ 0.054
    p1800 = fao.pressure_at_elevation_kpa(1800)
    expect(p1800).to be_within(0.05).of(81.8)
    expect(fao.psychrometric_constant_kpa_per_c(p1800)).to be_within(0.0005).of(0.054)
    # Example 5: a 15 °C dew point's actual vapour pressure
    expect(fao.vapor_pressure_kpa(15)).to be_within(0.001).of(1.705)
  end

  it "gives RH from the dew point, saturated when the dew point is above the temperature" do
    expect(fao.relative_humidity_percent(20, 20)).to be_within(1e-9).of(100)
    expect(fao.relative_humidity_percent(20, 25)).to be_within(1e-9).of(100)
    expect(fao.relative_humidity_percent(30, 10)).to be_within(0.1).of(28.9)
    expect(fao.relative_humidity_percent(20, 10)).to be_within(0.1).of(52.5)
    expect(fao.relative_humidity_percent(nil, 10)).to be_nil
  end

  it "inverts RH back to the dew point" do
    [[-20.0, -25.0], [0.0, -3.0], [15.0, 15.0], [32.0, 10.0]].each do |t, td|
      expect(fao.dew_point_from_rh_c(t, fao.relative_humidity_percent(t, td))).to be_within(1e-9).of(td)
    end
    expect(fao.dew_point_from_rh_c(nil, 50)).to be_nil
    expect(fao.dew_point_from_rh_c(20, 120)).to be_within(1e-9).of(20) # capped at saturation
  end

  [-122.0, -89.4, -75.0, 0.0, 100.0].each do |longitude|
    it "sums a solar day's 24 hourly Ra to eq. 21's daily Ra at longitude #{longitude}" do
      # The hour angle must wrap: west of Greenwich a summer evening's solar time by UTC is below 0 h
      latitude = 43.0
      noon = Time.utc(2025, 7, 2) + ((12 - longitude / 15) * 3600).round
      hourly = (1..24).sum { |k| fao.extraterrestrial_radiation_hourly(noon - 12 * 3600 + k * 3600, latitude, longitude) }
      j = 183
      dr = 1 + 0.033 * Math.cos(2 * Math::PI * j / 365)
      dec = 0.409 * Math.sin(2 * Math::PI * j / 365 - 1.39)
      phi = latitude * Math::PI / 180
      ws = Math.acos(-Math.tan(phi) * Math.tan(dec))
      daily = 24 * 60 / Math::PI * 0.082 * dr * (ws * Math.sin(phi) * Math.sin(dec) + Math.cos(phi) * Math.cos(dec) * Math.sin(ws))
      expect(hourly).to be_within(daily * 0.01).of(daily)
    end
  end

  it "matches Example 19's extraterrestrial radiation, day and night" do
    expect(fao.extraterrestrial_radiation_hourly(day_end, lat, lon)).to be_within(0.01).of(3.543)
    expect(fao.extraterrestrial_radiation_hourly(night_end, lat, lon)).to eq 0
  end

  it "matches Example 19's day hour" do
    ea = 0.52 * fao.saturation_vapor_pressure_kpa(38) # RH 52%
    expect(ea).to be_within(0.001).of(3.445)
    rso = (0.75 + 2e-5 * z) * fao.extraterrestrial_radiation_hourly(day_end, lat, lon)
    expect(rso).to be_within(0.01).of(2.658)
    rn = fao.net_radiation_hourly_mj(2.450, 2.450 / rso, 38, ea)
    expect(rn).to be_within(0.005).of(1.749)
    expect(fao.et0_hourly_mm(38, ea, 3.3, rn, 0.1 * rn, pressure)).to be_within(0.005).of(0.63)
  end

  it "matches Example 19's night hour" do
    ea = 0.90 * fao.saturation_vapor_pressure_kpa(28) # RH 90%
    rn = fao.net_radiation_hourly_mj(0.0, 0.8, 28, ea)
    expect(rn).to be_within(0.002).of(-0.100)
    expect(fao.et0_hourly_mm(28, ea, 1.9, rn, 0.5 * rn, pressure)).to be_within(0.005).of(0.0)
  end

  it "converts wind to 2 m (Example 14) and pressure to elevation" do
    expect(fao.wind_speed_2m(1.0)).to be_within(0.001).of(0.748)
    expect(fao.wind_speed_2m(3.2)).to be_within(0.01).of(2.4)
    expect(fao.elevation_from_pressure_m(pressure)).to be_within(0.5).of(z)
  end

  it "matches Examples 8 and 9: a day's Ra and length at 20°S on 3 September" do
    hours = (1..24).map { |k| Time.utc(2026, 9, 3) + k * 3600 } # a solar day at 0° longitude
    expect(hours.sum { |h| fao.extraterrestrial_radiation_hourly(h, -20.0, 0.0) }).to be_within(0.15).of(32.2)
    expect(fao.day_length_hours(246, -20.0, 0.0)).to be_within(0.05).of(11.7)
  end

  it "gives day length at the equinox and in polar summer and winter" do
    expect(fao.day_length_hours(80, 0.0, 0.0)).to be_within(0.15).of(12.0)
    expect(fao.day_length_hours(172, 70.0)).to eq 24
    expect(fao.day_length_hours(355, 70.0)).to eq 0
  end

  it "carries the last daytime cloudiness ratio overnight" do
    ratios = fao.cloudiness_ratios([0.0, 2.0, 1.0, 0.0, 0.0], [0.0, 2.5, 2.0, 0.1, 0.0], [-10, 40, 30, 5, -20])
    expect(ratios).to eq [0.8, 0.8, 0.5, 0.5, 0.5]
  end

  it "keeps heavy cloud from turning net longwave into a gain" do
    ratio = fao.cloudiness_ratios([50.0], [800.0], [45.0]).first
    expect(ratio).to eq described_class::RS_RSO_MIN
    expect(1.35 * ratio - 0.35).to be > 0
  end

  it "puts the sun high at a Madison June noon and below the horizon at midnight" do
    expect(fao.solar_elevation_deg(Time.utc(2026, 6, 21, 18), 43.07, -89.40)).to be_within(1.0).of(70.3)
    expect(fao.solar_elevation_deg(Time.utc(2026, 6, 21, 6), 43.07, -89.40)).to be < -20
  end

  it "sums a clear July day in Madison to a sensible ET0, peaking in the early afternoon" do
    hours = (0...24).map { |k| Time.utc(2026, 7, 15, 7) + k * 3600 }
    local = (0...24).map { |k| (k + 1 + 6 - 5) % 24 } # CDT hour ending
    temp = local.map { |h| 22 + 8 * Math.sin((h - 9) / 24.0 * 2 * Math::PI) }
    shortwave = hours.map { |h| [1000 * Math.sin(fao.radians([fao.solar_elevation_deg(h - 1800, 43.07, -89.40), 0].max)), 0].max * 0.8 }
    et0 = fao.et0_hourly_series(hour_ends: hours, latitude: 43.07, longitude: -89.40, temperature_c: temp,
      dew_point_c: temp.map { |t| t - 8 }, wind_speed_10m_m_s: [3.0] * 24, pressure_kpa: [98.0] * 24, shortwave_w_m2: shortwave)
    expect(et0.sum).to be_between(4.5, 7.5)
    expect(et0.index(et0.max)).to be_between(11, 14) # 13:00–16:00 CDT
  end

  it "gives nil ET0 for a missing input" do
    expect(fao.et0_hourly_mm(nil, 1.0, 2.0, 0.5, 0.05, 98.0)).to be_nil
    et0 = fao.et0_hourly_series(hour_ends: [Time.utc(2026, 7, 15, 18)], latitude: 43.07, longitude: -89.40,
      temperature_c: [25.0], dew_point_c: [15.0], wind_speed_10m_m_s: [3.0], pressure_kpa: [nil], shortwave_w_m2: [700.0])
    expect(et0).to eq [nil]
  end
end

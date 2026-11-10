module Weather
  # Weather physics from FAO Irrigation and Drainage Paper 56 (Allen, Pereira, Raes and Smith, 1998,
  # https://www.fao.org/4/x0490e/x0490e00.htm): humidity, the sun's geometry, clear-sky radiation and
  # the hourly Penman-Monteith grass reference ET0 (PLAN.md §8.5, D12). Ported from AgWeather v2's
  # `agmodels.weather` (at bbb0a6d), whose results WISP's corrected weather must match
  # (spec/services/weather/fao56_spec.rb, weather_corrections_spec.rb).
  #
  # Plain functions on numbers; a nil input gives nil. Times are UTC `Time`s, and an hourly value
  # stamped t covers the hour ending at t. Units are SI unless the name says otherwise: °C, kPa, m/s,
  # MJ/m² per hour for radiation, W/m² for a mean flux.
  module Fao56
    SOLAR_CONSTANT = 0.0820 # MJ m-2 min-1
    STEFAN_BOLTZMANN_HOURLY = 2.043e-10 # MJ K-4 m-2 h-1 (eq. 39 for hourly steps)
    ALBEDO_GRASS = 0.23
    # ASCE-EWRI (2005): below this sun elevation Rs/Rso is unreliable, so the last value above it carries on
    CLOUDINESS_MIN_ELEVATION_DEG = 17.2
    # ASCE-EWRI (2005) eq. 45 keeps the cloudiness factor 1.35 Rs/Rso − 0.35 within 0.05–1, so Rs/Rso within
    # 0.3–1: below 0.3 heavy cloud would turn net longwave into a gain
    RS_RSO_MIN = 0.3
    DEFAULT_RS_RSO = 0.8 # before any daytime value to carry (Example 19's night assumption)
    # Where an hour has no pressure, clear-sky radiation takes this (only its elevation term uses it)
    FALLBACK_PRESSURE_KPA = 97.0
    W_M2_HOUR_TO_MJ = 0.0036 # a mean W/m² over an hour, in MJ/m²

    module_function

    # Humidity

    # e°(T), eq. 11
    def saturation_vapor_pressure_kpa(temperature_c)
      return if temperature_c.nil?
      0.6108 * Math.exp(17.27 * temperature_c / (temperature_c + 237.3))
    end

    # Actual vapor pressure from the dew point, eq. 14
    def vapor_pressure_kpa(dew_point_c) = saturation_vapor_pressure_kpa(dew_point_c)

    # RH 0–100 from temperature and dew point (a dew point above the temperature counts as saturated)
    def relative_humidity_percent(temperature_c, dew_point_c)
      return if temperature_c.nil? || dew_point_c.nil?
      (100 * vapor_pressure_kpa(dew_point_c) / saturation_vapor_pressure_kpa(temperature_c)).clamp(0.0, 100.0)
    end

    # The inverse of relative_humidity_percent (RH below 0.1% taken as 0.1%, above 100 as 100)
    def dew_point_from_rh_c(temperature_c, rh_percent)
      return if temperature_c.nil? || rh_percent.nil?
      e = rh_percent.clamp(0.1, 100.0) / 100 * saturation_vapor_pressure_kpa(temperature_c)
      g = Math.log(e / 0.6108)
      237.3 * g / (17.27 - g)
    end

    # Δ, eq. 13
    def svp_slope_kpa_per_c(temperature_c)
      return if temperature_c.nil?
      4098 * saturation_vapor_pressure_kpa(temperature_c) / (temperature_c + 237.3)**2
    end

    # γ, eq. 8
    def psychrometric_constant_kpa_per_c(pressure_kpa) = pressure_kpa && 0.000665 * pressure_kpa

    # Pressure at an elevation, eq. 7
    def pressure_at_elevation_kpa(elevation_m) = 101.3 * ((293 - 0.0065 * elevation_m) / 293)**5.26

    # Elevation from surface pressure, eq. 7 inverted (for Rso without an elevation at hand)
    def elevation_from_pressure_m(pressure_kpa)
      return if pressure_kpa.nil?
      (293 - 293 * (pressure_kpa / 101.3)**(1 / 5.26)) / 0.0065
    end

    # Wind at 2 m from wind at 10 m over short grass, eq. 47
    def wind_speed_2m(wind_speed_10m) = wind_speed_10m && wind_speed_10m * 4.87 / Math.log(67.8 * 10 - 5.42)

    # Sun

    # Declination (eq. 24), inverse relative Earth-Sun distance (eq. 23) and the hour angle (eq. 31)
    # in radians, from solar noon and wrapped to ±π: west of Greenwich a summer evening's solar time by
    # UTC is below 0 h, and without the wrap its hours get no sun (v2's bug until 2026-10-31)
    def solar_terms(time, longitude_deg)
      time = time.utc
      j = time.yday
      declination = 0.409 * Math.sin(2 * Math::PI * j / 365 - 1.39)
      dr = 1 + 0.033 * Math.cos(2 * Math::PI * j / 365)
      b = 2 * Math::PI * (j - 81) / 364
      seasonal_correction_h = 0.1645 * Math.sin(2 * b) - 0.1255 * Math.cos(b) - 0.025 * Math.sin(b) # eq. 32-33
      hours_utc = time.hour + time.min / 60.0 + time.sec / 3600.0
      # UTC plus the longitude's offset is local solar time (Lz = 0 in eq. 31, east positive)
      solar_time_h = hours_utc + longitude_deg / 15.0 + seasonal_correction_h
      [declination, dr, Math::PI / 12 * (solar_time_h % 24 - 12)]
    end

    # The sun's elevation above the horizon at a time, degrees
    def solar_elevation_deg(time, latitude_deg, longitude_deg)
      declination, _, hour_angle = solar_terms(time, longitude_deg)
      lat = radians(latitude_deg)
      sin_elevation = Math.sin(lat) * Math.sin(declination) + Math.cos(lat) * Math.cos(declination) * Math.cos(hour_angle)
      degrees(Math.asin(sin_elevation.clamp(-1.0, 1.0)))
    end

    # Hours with the sun's centre above sun_elevation_deg (−0.83°: sunrise to sunset), 24 or 0 where
    # it doesn't cross it
    def day_length_hours(day_of_year, latitude_deg, sun_elevation_deg = -0.83)
      declination = 0.409 * Math.sin(2 * Math::PI * day_of_year / 365 - 1.39)
      lat = radians(latitude_deg)
      cos_h = (Math.sin(radians(sun_elevation_deg)) - Math.sin(lat) * Math.sin(declination)) /
        (Math.cos(lat) * Math.cos(declination))
      24 / Math::PI * Math.acos(cos_h.clamp(-1.0, 1.0))
    end

    # Ra over the hour ending at hour_end, MJ m-2 h-1, eq. 28 (0 while the sun is down)
    def extraterrestrial_radiation_hourly(hour_end, latitude_deg, longitude_deg)
      declination, dr, omega = solar_terms(hour_end - 1800, longitude_deg)
      lat = radians(latitude_deg)
      sunset = Math.acos((-Math.tan(lat) * Math.tan(declination)).clamp(-1.0, 1.0)) # eq. 25
      omega1 = (omega - Math::PI / 24).clamp(-sunset, sunset) # eq. 29-30, within the daylight hours
      omega2 = (omega + Math::PI / 24).clamp(-sunset, sunset)
      ra = 12 * 60 / Math::PI * SOLAR_CONSTANT * dr *
        ((omega2 - omega1) * Math.sin(lat) * Math.sin(declination) +
          Math.cos(lat) * Math.cos(declination) * (Math.sin(omega2) - Math.sin(omega1)))
      [ra, 0.0].max
    end

    # Clear-sky Rso (eq. 37) as a mean flux over the hour, W/m², with the elevation from the hour's
    # pressure (FALLBACK_PRESSURE_KPA where it's missing), so never nil
    def clear_sky_shortwave_w_m2(hour_end, latitude_deg, longitude_deg, pressure_kpa)
      elevation = elevation_from_pressure_m(pressure_kpa || FALLBACK_PRESSURE_KPA)
      (0.75 + 2e-5 * elevation) * extraterrestrial_radiation_hourly(hour_end, latitude_deg, longitude_deg) / W_M2_HOUR_TO_MJ
    end

    # Reference evapotranspiration

    # Rs/Rso for net longwave (RS_RSO_MIN–1) at each hour, carried forward while the sun is too low to
    # measure it; hours before the first usable value take DEFAULT_RS_RSO
    def cloudiness_ratios(rs, rso, sun_elevation_deg)
      last = DEFAULT_RS_RSO
      rs.each_index.map do |k|
        if !rs[k].nil? && !rso[k].nil? && rso[k] > 0 && sun_elevation_deg[k] > CLOUDINESS_MIN_ELEVATION_DEG
          last = (rs[k] / rso[k]).clamp(RS_RSO_MIN, 1.0)
        end
        last
      end
    end

    # Rn = Rns − Rnl over an hour, MJ m-2 h-1 (eq. 38-40, hourly σ)
    def net_radiation_hourly_mj(rs_mj, rs_rso, temperature_c, vapor_pressure_kpa)
      return if [rs_mj, rs_rso, temperature_c, vapor_pressure_kpa].any?(&:nil?)
      t_k = temperature_c + 273.16
      rnl = STEFAN_BOLTZMANN_HOURLY * t_k**4 * (0.34 - 0.14 * Math.sqrt(vapor_pressure_kpa)) * (1.35 * rs_rso - 0.35)
      (1 - ALBEDO_GRASS) * rs_mj - rnl
    end

    # The Penman-Monteith grass reference ET0 for one hour, mm (eq. 53); negative (dew) becomes 0
    def et0_hourly_mm(temperature_c, vapor_pressure_kpa, wind_speed_2m_m_s, net_radiation_mj, soil_heat_flux_mj, pressure_kpa)
      inputs = [temperature_c, vapor_pressure_kpa, wind_speed_2m_m_s, net_radiation_mj, soil_heat_flux_mj, pressure_kpa]
      return if inputs.any?(&:nil?)
      delta = svp_slope_kpa_per_c(temperature_c)
      gamma = psychrometric_constant_kpa_per_c(pressure_kpa)
      deficit = saturation_vapor_pressure_kpa(temperature_c) - vapor_pressure_kpa
      numerator = 0.408 * delta * (net_radiation_mj - soil_heat_flux_mj) +
        gamma * 37 / (temperature_c + 273) * wind_speed_2m_m_s * deficit
      [numerator / (delta + gamma * (1 + 0.34 * wind_speed_2m_m_s)), 0.0].max
    end

    # Hourly ET0 (mm) for a point's series of hours: the whole hourly chain from the stored variables.
    # Shortwave is each hour's mean flux (W/m²); the soil heat flux is 0.1 Rn by day and 0.5 Rn at
    # night (eq. 45-46). The cloudiness ratio carries across the whole series, as in v2.
    def et0_hourly_series(hour_ends:, latitude:, longitude:, temperature_c:, dew_point_c:, wind_speed_10m_m_s:, pressure_kpa:, shortwave_w_m2:)
      rs = shortwave_w_m2.map { |w| w && w * W_M2_HOUR_TO_MJ }
      ra = hour_ends.map { |time| extraterrestrial_radiation_hourly(time, latitude, longitude) }
      rso = ra.each_with_index.map do |r, k|
        elevation = elevation_from_pressure_m(pressure_kpa[k])
        elevation && (0.75 + 2e-5 * elevation) * r
      end
      sun = hour_ends.map { |time| solar_elevation_deg(time - 1800, latitude, longitude) }
      ratios = cloudiness_ratios(rs, rso, sun)
      hour_ends.each_index.map do |k|
        ea = vapor_pressure_kpa(dew_point_c[k])
        rn = net_radiation_hourly_mj(rs[k], ratios[k], temperature_c[k], ea)
        g = rn && ((ra[k] > 0) ? 0.1 : 0.5) * rn
        et0_hourly_mm(temperature_c[k], ea, wind_speed_2m(wind_speed_10m_m_s[k]), rn, g, pressure_kpa[k])
      end
    end

    def radians(degrees) = degrees * Math::PI / 180

    def degrees(radians) = radians * 180 / Math::PI
  end
end

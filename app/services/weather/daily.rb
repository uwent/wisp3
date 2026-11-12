module Weather
  # Turns a location's hours (Weather::Hours: merged across models, corrected, metric) into daily
  # values in WISP's units by local day, keyed like WeatherDay::VALUE_COLUMNS, with "corrections"
  # listing the corrections the day's values went through. A value is nil when more than
  # MAX_MISSING_HOURS of its day are missing (as in Ben's R client), or when no model provides it.
  module Daily
    MAX_MISSING_HOURS = 2
    MM_PER_IN = 25.4
    KMH_PER_MPH = 1.609344

    c_to_f = ->(c) { c * 9 / 5.0 + 32 }
    mm_to_in = ->(mm) { mm / MM_PER_IN }
    kmh_to_mph = ->(kmh) { kmh / KMH_PER_MPH }
    w_m2_to_mj = ->(w_m2_hours) { w_m2_hours * Fao56::W_M2_HOUR_TO_MJ }
    same = ->(value) { value }

    # column => [hourly variable, how hours combine, conversion]
    COLUMNS = {
      "et0_in" => ["et0", :sum, mm_to_in], # FAO-56 from the corrected hours
      "et0_openmeteo_in" => ["et0_fao_evapotranspiration", :sum, mm_to_in],
      "shortwave_mj" => ["shortwave_radiation", :sum, w_m2_to_mj],
      "shortwave_raw_mj" => ["shortwave_radiation_raw", :sum, w_m2_to_mj],
      "precip_in" => ["precipitation", :sum, mm_to_in],
      "rain_in" => ["rain", :sum, mm_to_in],
      "snowfall_in" => ["snowfall", :sum, ->(cm) { cm * 10 / MM_PER_IN }],
      "snow_depth_in" => ["snow_depth", :max, ->(m) { m * 1000 / MM_PER_IN }],
      "tmax_f" => ["temperature_2m", :max, c_to_f],
      "tmin_f" => ["temperature_2m", :min, c_to_f],
      "tmean_f" => ["temperature_2m", :mean, c_to_f],
      "dew_point_f" => ["dew_point_2m", :mean, c_to_f],
      "dew_point_raw_f" => ["dew_point_2m_raw", :mean, c_to_f],
      "rh_mean_pct" => ["relative_humidity", :mean, same],
      "rh_min_pct" => ["relative_humidity", :min, same],
      "rh_max_pct" => ["relative_humidity", :max, same],
      "rh_mean_raw_pct" => ["relative_humidity_raw", :mean, same],
      "rh_min_raw_pct" => ["relative_humidity_raw", :min, same],
      "rh_max_raw_pct" => ["relative_humidity_raw", :max, same],
      "vpd_max_kpa" => ["vapour_pressure_deficit", :max, same],
      "pressure_msl_hpa" => ["pressure_msl", :mean, same],
      "wind_speed_mph" => ["wind_speed_10m", :mean, kmh_to_mph],
      "wind_speed_max_mph" => ["wind_speed_10m", :max, kmh_to_mph],
      "wind_gust_max_mph" => ["wind_gusts_10m", :max, kmh_to_mph],
      "wind_direction_deg" => ["wind_direction_10m", :direction, same],
      "cloud_cover_pct" => ["cloud_cover", :mean, same],
      "cloud_cover_low_pct" => ["cloud_cover_low", :mean, same],
      "cloud_cover_mid_pct" => ["cloud_cover_mid", :mean, same],
      "cloud_cover_high_pct" => ["cloud_cover_high", :mean, same],
      # The day's most severe hour, as Open-Meteo's own daily weather_code (WMO codes rise with severity)
      "weather_code" => ["weather_code", :max, ->(code) { code.round }],
      "soil_temp_0_7cm_f" => ["soil_temperature_0_to_7cm", :mean, c_to_f],
      "soil_temp_7_28cm_f" => ["soil_temperature_7_to_28cm", :mean, c_to_f],
      "soil_temp_28_100cm_f" => ["soil_temperature_28_to_100cm", :mean, c_to_f],
      "soil_temp_100_255cm_f" => ["soil_temperature_100_to_255cm", :mean, c_to_f],
      "soil_moisture_0_7cm" => ["soil_moisture_0_to_7cm", :mean, same],
      "soil_moisture_7_28cm" => ["soil_moisture_7_to_28cm", :mean, same],
      "soil_moisture_28_100cm" => ["soil_moisture_28_to_100cm", :mean, same],
      "soil_moisture_100_255cm" => ["soil_moisture_100_to_255cm", :mean, same]
    }.freeze
    # The column whose value says a day went through each correction
    CORRECTED_COLUMNS = {Corrections::SHORTWAVE => "shortwave_mj", Corrections::RH => "dew_point_f", Corrections::ET0 => "et0_in"}.freeze

    module_function

    # {date => {"hours" => n, column => value, ..., "corrections" => [label, ...]}} from one or more
    # Hourly responses for the same location, in order of preference (e.g. NBM, then best_match,
    # then the soil model), merged hour by hour and corrected at the location's point
    def from_hourly(*responses, latitude:, longitude:)
      from_hours(Hours.merge(*responses).corrected(latitude:, longitude:))
    end

    def from_hours(hours)
      dates = hours.dates
      labels = hours.corrections.to_h { |id| [id, Corrections.label(id)] }
      dates.each_index.group_by { |i| dates[i] }.to_h do |date, indexes|
        day = {"hours" => indexes.size}
        COLUMNS.each do |column, (variable, method, convert)|
          series = hours.values[variable]
          value = series.presence && combine(indexes.map { |i| series[i] }, method, indexes.size)
          day[column] = value && convert.call(value)
        end
        day["corrections"] = labels.filter_map { |id, label| label unless day[CORRECTED_COLUMNS.fetch(id)].nil? }
        [date, day]
      end
    end

    def combine(values, method, expected_hours)
      present = values.compact
      return if present.size < expected_hours - MAX_MISSING_HOURS || present.empty?
      case method
      when :sum then present.sum
      when :max then present.max
      when :min then present.min
      when :mean then present.sum / present.size
      when :direction then mean_direction(present)
      end
    end

    # Mean of compass directions, via unit vectors (so 350° and 10° average to 0°, not 180°)
    def mean_direction(degrees)
      radians = degrees.map { |d| d * Math::PI / 180 }
      x = radians.sum { |r| Math.cos(r) }
      y = radians.sum { |r| Math.sin(r) }
      return if x.abs < 1e-9 && y.abs < 1e-9
      (Math.atan2(y, x) * 180 / Math::PI) % 360
    end
  end
end

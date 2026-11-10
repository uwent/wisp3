module Weather
  # One location's hourly values, merged across models hour by hour and corrected (PLAN.md §8.5,
  # D12), before Weather::Daily aggregates them to local days. As AgWeather v2 does it
  # (`agdata.sources.openmeteo.fetch` and `correct`):
  #
  # 1. merge: each variable's hour comes from the first response that has it (NBM, then best_match,
  #    then the soil model), so ET0 can be computed from whole hours;
  # 2. correct: shortwave by its clearness and the dew point by the RH map (Weather::Corrections),
  #    keeping the values before as "<variable>_raw";
  # 3. derive from the corrected hours: RH and the vapor pressure deficit from temperature and dew
  #    point, and FAO-56's hourly ET0 ("et0", mm; Weather::Fao56). Open-Meteo's own ET0 stays as
  #    "et0_fao_evapotranspiration", the raw value.
  #
  # times are UTC `Time`s, each the end of its hour; values are in Open-Meteo's metric units.
  Hours = Data.define(:times, :time_zone, :values, :corrections) do
    def self.merge(*responses)
      responses = responses.flatten.compact
      index = responses.flat_map(&:times).uniq.sort.each_with_index.to_h
      values = {}
      responses.each do |response|
        positions = response.times.map { |time| index[time] }
        response.values.each do |variable, series|
          next if series.blank?
          merged = values[variable] ||= Array.new(index.size)
          positions.each_with_index { |k, i| merged[k] = series[i] if merged[k].nil? }
        end
      end
      time_zone = ActiveSupport::TimeZone[responses.first&.timezone || Time.zone.name]
      new(times: index.keys, time_zone:, values:, corrections: [])
    end

    # The local date of each hour (a DST day has 23 or 25)
    def dates = times.map { |time| time.in_time_zone(time_zone).to_date }

    def series(variable) = values[variable] || Array.new(times.size)

    # The hours with the corrections applied and RH, VPD and ET0 derived, at the cell's point
    def corrected(latitude:, longitude:)
      v = values.dup
      temperature = series("temperature_2m")
      pressure = series("surface_pressure").map { |hpa| hpa && hpa / 10.0 }
      applied = []
      if values["shortwave_radiation"]
        v["shortwave_radiation_raw"] = values["shortwave_radiation"]
        v["shortwave_radiation"] = Corrections.shortwave(hour_ends: times, latitude:, longitude:,
          shortwave_w_m2: values["shortwave_radiation"], pressure_kpa: pressure)
        applied << Corrections::SHORTWAVE
      end
      if values["dew_point_2m"]
        v["dew_point_2m_raw"] = values["dew_point_2m"]
        v["dew_point_2m"] = Corrections.dew_point(hour_ends: times, longitude:, temperature_c: temperature,
          dew_point_c: values["dew_point_2m"])
        applied << Corrections::RH
      end
      dew_point = v["dew_point_2m"] || Array.new(times.size)
      v["relative_humidity"] = temperature.zip(dew_point).map { |t, td| Fao56.relative_humidity_percent(t, td) }
      v["relative_humidity_raw"] = temperature.zip(series("dew_point_2m")).map { |t, td| Fao56.relative_humidity_percent(t, td) }
      v["vapour_pressure_deficit"] = temperature.zip(dew_point).map do |t, td|
        t && td && [Fao56.saturation_vapor_pressure_kpa(t) - Fao56.vapor_pressure_kpa(td), 0.0].max
      end
      v["et0"] = Fao56.et0_hourly_series(hour_ends: times, latitude:, longitude:, temperature_c: temperature,
        dew_point_c: dew_point, wind_speed_10m_m_s: series("wind_speed_10m").map { |kmh| kmh && kmh / 3.6 },
        pressure_kpa: pressure, shortwave_w_m2: v["shortwave_radiation"] || Array.new(times.size))
      applied << Corrections::ET0
      with(values: v, corrections: applied)
    end
  end
end

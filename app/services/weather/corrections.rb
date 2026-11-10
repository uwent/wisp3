module Weather
  # The corrections to Open-Meteo's hourly weather (PLAN.md D12, §8.5), from the tables in
  # db/reference/weather_corrections (copied from AgWeather v2; its README says from where).
  # `shortwave` and `dew_point` correct one point's hours; `all` describes each correction for the
  # About page and the admin weather page; `label` is what a stored day records it went through.
  module Corrections
    DIR = Rails.root.join("db/reference/weather_corrections")
    SHORTWAVE = "openmeteo-shortwave"
    RH = "openmeteo-rh"
    ET0 = "et0-fao56"
    ENSEMBLE_ET0 = "et0-ensemble-ratio"

    Correction = Data.define(:id, :variable, :method, :fitted_against, :effect, :evidence, :version, :fitted, :source, :table) do
      def label = "#{id} v#{version}"
    end

    module_function

    def all = @all ||= load

    def find(id) = all.find { |c| c.id == id } || raise(KeyError, "no weather correction #{id}")

    def label(id) = find(id).label

    def table(id) = find(id).table

    # Each hour's shortwave (mean W/m² over the hour ending at hour_ends[k]) scaled by the factor for
    # its clearness, Rs over FAO-56's clear-sky Rso: linear between the table's bins and held at its
    # ends. An hour whose Rso is 1 W/m² or less (the sun down) takes clearness 0, so a dark hour's 0
    # stays 0 and a twilight hour's few W/m² take the darkest bin's factor (v2's code, not §8.5's
    # words). Missing stays nil, and the result is never negative.
    def shortwave(hour_ends:, latitude:, longitude:, shortwave_w_m2:, pressure_kpa:)
      bins = table(SHORTWAVE)
      hour_ends.each_with_index.map do |time, k|
        raw = shortwave_w_m2[k]
        next if raw.nil?
        rso = Fao56.clear_sky_shortwave_w_m2(time, latitude, longitude, pressure_kpa[k])
        clearness = (rso > 1) ? raw / rso : 0.0
        [raw * interpolate(clearness, bins.fetch("clearness"), bins.fetch("factor")), 0.0].max
      end
    end

    # Each hour's dew point after quantile-mapping its RH (from temperature and dew point) by season
    # and solar hour, temperature kept (v2's calibration.map_humidity with its one lead group). nil
    # where either input is.
    def dew_point(hour_ends:, longitude:, temperature_c:, dew_point_c:)
      map = table(RH)
      hour_ends.each_with_index.map do |time, k|
        t = temperature_c[k]
        rh = Fao56.relative_humidity_percent(t, dew_point_c[k])
        next if rh.nil?
        [Fao56.dew_point_from_rh_c(t, map_rh(map, time, longitude, rh)), t].min
      end
    end

    # One hour's RH through the map (v2's calibration.map_rh): blended between the two seasons around
    # its day of year (around the year's end), the two solar-hour bins around it (centred on h + 0.5)
    # and the two RH grid points around the value
    def map_rh(map, time, longitude, rh)
      time = time.utc
      grid = map.fetch("rh_grid")
      seasons = map.fetch("map")
      x = rh.clamp(grid.first.to_f, grid.last.to_f)
      i0 = x.floor.clamp(0, grid.size - 2)
      f = x - grid[i0]
      hour = (time.hour + time.min / 60.0 + longitude / 15.0) % 24 - 0.5
      h0 = hour.floor % 24
      wh = hour - hour.floor
      h1 = (h0 + 1) % 24
      season_neighbours(time.yday + time.hour / 24.0, map.fetch("season_day_of_year")).sum do |season, weight|
        bins = seasons[season][0]
        lower = (1 - f) * bins[h0][i0] + f * bins[h0][i0 + 1]
        upper = (1 - f) * bins[h1][i0] + f * bins[h1][i0 + 1]
        weight * ((1 - wh) * lower + wh * upper)
      end
    end

    # The two season centres around a day of year and their weights, around a 365-day year
    def season_neighbours(day, centres, period = 365)
      d = day % period
      k = centres.rindex { |c| c <= d } || centres.size - 1
      lo, hi = k, (k + 1) % centres.size
      span = (centres[hi] - centres[lo]) % period
      span = period if span.zero?
      w = ((day - centres[lo]) % period) / span.to_f
      [[lo, 1 - w], [hi, w]]
    end

    # np.interp: linear between the points, held at the ends
    def interpolate(x, xs, ys)
      return ys.first if x <= xs.first
      return ys.last if x >= xs.last
      i = xs.rindex { |v| v <= x }
      ys[i] + (ys[i + 1] - ys[i]) * (x - xs[i]) / (xs[i + 1] - xs[i])
    end

    def load
      YAML.safe_load_file(DIR.join("corrections.yml")).fetch("corrections").map do |entry|
        table = entry["table"] && JSON.parse(DIR.join(entry["table"]).read)
        Correction.new(
          id: entry.fetch("id"), variable: entry.fetch("variable"), method: entry.fetch("method"),
          fitted_against: entry.fetch("fitted_against"), effect: entry.fetch("effect"), evidence: entry.fetch("evidence"),
          version: (table || entry).fetch("version").to_s, fitted: (table || entry).fetch("fitted").to_s,
          source: table&.dig("source"), table:
        )
      end.freeze
    end
  end
end

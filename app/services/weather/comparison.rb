require "net/http"

module Weather
  # The AgWeather → Open-Meteo comparison (PLAN.md §8.4): daily reference ET and precipitation
  # from AgWeather (legacy WISP's source) against Open-Meteo models at the same points, and what
  # the difference does to a standard field's water balance. bin/rails weather:compare writes the
  # report. Uses the historical-forecast API, as the backfill does.
  class Comparison
    AGWEATHER = "https://agweather.cals.wisc.edu/api"
    MODELS = %w[best_match ncep_nbm_conus ecmwf_ifs].freeze
    RAIN_DAY_IN = 0.05

    # Irrigated areas of Wisconsin, standing in for real pivot locations
    DEFAULT_POINTS = [
      ["Hancock", 44.12, -89.53], ["Plainfield", 44.21, -89.49], ["Coloma", 44.03, -89.52],
      ["Almond", 44.26, -89.41], ["Bancroft", 44.31, -89.51], ["Plover", 44.45, -89.54],
      ["Wautoma", 44.07, -89.29], ["Grand Marsh", 43.89, -89.71], ["Arena", 43.17, -89.91],
      ["Spring Green", 43.18, -90.07], ["Antigo", 45.14, -89.15], ["Janesville", 42.68, -89.02]
    ].freeze

    # A standard potato field: sand, 16 in roots, MAD 0.5, emergence May 20, full cover by July 1,
    # irrigated 0.75 in the day after AD reaches 0
    FIELD = {field_capacity: 0.15, perm_wilting_pt: 0.05, max_root_zone_depth: 16.0, mad_frac: 0.5}.freeze
    IRRIGATION_IN = 0.75

    Series = Data.define(:et0, :precip) # {date => inches}

    def initialize(points: DEFAULT_POINTS, years: [2025, 2026], client: OpenMeteo.new, log: ->(_) {})
      @points, @years, @client, @log = points, years, client, log
    end

    def season(year)
      first, last = Date.new(year, 4, 1), Date.new(year, 9, 30)
      first..[last, Date.current - 2].min
    end

    # {[point name, year] => {"agweather" => Series, model => Series}}
    def data
      @data ||= @years.each_with_object({}) do |year, result|
        dates = season(year)
        models = MODELS.to_h { |model| [model, open_meteo(model, dates)] }
        @points.each_with_index do |(name, lat, lng), i|
          @log.call("#{year} #{name}")
          result[[name, year]] = {"agweather" => agweather(lat, lng, dates)}.merge(models.transform_values { |series| series[i] })
        end
      end
    end

    # Per source and variable, over all points and years: totals and daily error statistics vs AgWeather
    def stats
      sources = MODELS
      %i[et0 precip].to_h do |variable|
        [variable, sources.to_h do |source|
          pairs = data.values.flat_map do |by_source|
            reference, other = by_source["agweather"].public_send(variable), by_source[source].public_send(variable)
            reference.filter_map { |date, ref| [ref, other[date]] if ref && other[date] }
          end
          [source, summarize(pairs, variable)]
        end]
      end
    end

    # Per point/year and source: irrigations, inches applied, first irrigation date
    def balances
      data.transform_values { |by_source| by_source.transform_values { |series| simulate(series) } }
    end

    def simulate(series)
      params = WaterBalance::Params.new(**FIELD)
      ad = params.initial_ad
      history = []
      irrigations = []
      pending = false
      series.et0.keys.sort.each do |date|
        emergence = Date.new(date.year, 5, 20)
        cover = ((date - emergence).to_f / (Date.new(date.year, 7, 1) - emergence) * 100).clamp(0, 100)
        irrigation = pending ? IRRIGATION_IN : 0.0
        irrigations << date if pending
        day = WaterBalance::Day.new(date:, et0: series.et0[date], rain: series.precip[date], irrigation:, canopy: cover)
        result = WaterBalance.run(params, [day], initial_ad: ad, et_history: history).first
        history << [date, result.adj_et] if result.et_source == :computed
        ad = result.ad
        pending = ad <= 0
      end
      {count: irrigations.size, inches: irrigations.size * IRRIGATION_IN, first: irrigations.first}
    end

    private

    def summarize(pairs, variable)
      return {} if pairs.empty?
      refs, values = pairs.map(&:first), pairs.map(&:last)
      diffs = values.zip(refs).map { |v, r| v - r }
      n = pairs.size
      mean_ref, mean_val = refs.sum / n, values.sum / n
      cov = refs.zip(values).sum { |r, v| (r - mean_ref) * (v - mean_val) }
      sd = ->(xs, m) { Math.sqrt(xs.sum { |x| (x - m)**2 }) }
      stats = {
        days: n, reference_mean: mean_ref, mean: mean_val, bias: diffs.sum / n, ratio: (mean_ref.zero? ? nil : mean_val / mean_ref),
        mae: diffs.sum(&:abs) / n, rmse: Math.sqrt(diffs.sum { |d| d * d } / n),
        r: (sd.call(refs, mean_ref) * sd.call(values, mean_val)).then { |den| den.zero? ? nil : cov / den }
      }
      if variable == :precip
        wet = pairs.map { |r, v| [r >= RAIN_DAY_IN, v >= RAIN_DAY_IN] }
        stats[:rain_days_reference] = wet.count(&:first)
        stats[:rain_days] = wet.count(&:last)
        stats[:rain_day_agreement] = wet.count { |a, b| a == b }.fdiv(n)
      end
      stats
    end

    def agweather(lat, lng, dates)
      et0, precip = %w[evapotranspirations precips].map do |resource|
        uri = URI("#{AGWEATHER}/#{resource}?" + URI.encode_www_form(lat: lat.round(1), long: lng.round(1),
          start_date: dates.first, end_date: dates.last, units: "in"))
        JSON.parse(Net::HTTP.get(uri)).fetch("data").to_h { |day| [Date.parse(day["date"]), day["value"]] }
      end
      Series.new(et0:, precip:)
    end

    def open_meteo(model, dates)
      locations = @points.map { |_, lat, lng|
        cell = Grid.cell_for(lat, lng)
        [cell.latitude, cell.longitude]
      }
      @client.hourly(locations, endpoint: :historical_forecast, model:,
        variables: %w[et0_fao_evapotranspiration precipitation], start_date: dates.first, end_date: dates.last).map do |hourly|
        days = Daily.from_hourly(hourly)
        Series.new(et0: days.transform_values { |d| d["et0_in"] }, precip: days.transform_values { |d| d["precip_in"] })
      end
    end
  end
end

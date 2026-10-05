module Weather
  # Turns a location's hourly ensemble response (Weather::OpenMeteo::ENSEMBLE_MODEL) into each
  # member's daily et0 and precipitation in inches, from today (local) on: the payload of an
  # ensemble WeatherForecast. A member's day is nil when more than Daily::MAX_MISSING_HOURS of it
  # are missing.
  module Ensemble
    SERIES = {"et0_in" => "et0_fao_evapotranspiration", "precip_in" => "precipitation"}.freeze

    module_function

    # {"dates" => [iso, ...], "members" => [{"et0_in" => [...], "precip_in" => [...]}, ...]}
    def from_hourly(response, today:)
      dates = response.times.map { |time| Date.parse(time) }
      indexes_by_date = dates.each_index.group_by { |i| dates[i] }.select { |date, _| date >= today }.sort.to_h

      members = member_suffixes(response).map do |suffix|
        SERIES.to_h do |column, variable|
          series = response.values["#{variable}#{suffix}"] || []
          [column, indexes_by_date.map do |_, indexes|
            total = Daily.combine(indexes.map { |i| series[i] }, :sum, indexes.size)
            total && (total / Daily::MM_PER_IN).round(4)
          end]
        end
      end
      {"dates" => indexes_by_date.keys.map(&:iso8601), "members" => members}
    end

    # "" (the control) and "_member01", "_member02", ... for the members in the response
    def member_suffixes(response)
      prefix = "#{SERIES.values.first}_member"
      numbers = response.values.keys.filter_map { |key| key.delete_prefix(prefix) if key.start_with?(prefix) }.sort
      [""] + numbers.map { |number| "_member#{number}" }
    end
  end
end

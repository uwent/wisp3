module Weather
  # Turns a location's hourly ensemble response (Weather::OpenMeteo::ENSEMBLE_MODEL) into each
  # member's daily et0 and precipitation in inches, from today (local) on: the payload of an
  # ensemble WeatherForecast. A member's day is nil when more than Daily::MAX_MISSING_HOURS of it
  # are missing.
  #
  # The members' ET0 is Open-Meteo's, so `corrected` scales it by the deterministic forecast's
  # corrected/raw ratio for the same day (PLAN.md Q10: not computed per member, which would triple
  # the ensemble's API calls; to be checked against a season of the forecast archive).
  module Ensemble
    SERIES = {"et0_in" => "et0_fao_evapotranspiration", "precip_in" => "precipitation"}.freeze

    module_function

    # {"dates" => [iso, ...], "members" => [{"et0_in" => [...], "precip_in" => [...]}, ...]}
    def from_hourly(response, today:)
      dates = Hours.merge(response).dates
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

    # A day's ratio is used only where the deterministic forecast's raw ET0 is at least this; other
    # days take the mean ratio of the days that have one
    MIN_RAW_ET0_IN = 0.01

    # The payload with each member's et0_in scaled by the deterministic forecast's et0_in over
    # et0_openmeteo_in for its date, the ratio kept by date ("et0_ratio", so the raw values can be
    # recovered) and the correction recorded ("corrections"). Unchanged when the forecast has no
    # ratio for any day (none yet, or one stored before the corrections).
    def corrected(payload, forecast)
      days = forecast&.payload&.fetch("days", nil) || []
      ratios = days.to_h do |day|
        raw, corrected = day.values_at("et0_openmeteo_in", "et0_in")
        [day["date"], (raw && corrected && raw >= MIN_RAW_ET0_IN) ? corrected / raw : nil]
      end.compact
      return payload if ratios.empty?
      mean = ratios.values.sum / ratios.size
      by_date = payload["dates"].map { |date| (ratios[date] || mean).round(4) }
      members = payload["members"].map do |member|
        member.merge("et0_in" => member["et0_in"].zip(by_date).map { |et0, ratio| et0 && (et0 * ratio).round(4) })
      end
      payload.merge("members" => members, "et0_ratio" => by_date, "corrections" => [Corrections.label(Corrections::ENSEMBLE_ET0)])
    end

    # "" (the control) and "_member01", "_member02", ... for the members in the response
    def member_suffixes(response)
      prefix = "#{SERIES.values.first}_member"
      numbers = response.values.keys.filter_map { |key| key.delete_prefix(prefix) if key.start_with?(prefix) }.sort
      [""] + numbers.map { |number| "_member#{number}" }
    end
  end
end

# Markdown report for Weather::Comparison (bin/rails weather:compare)
class WeatherComparisonReport
  LABELS = {"agweather" => "AgWeather", "best_match" => "Open-Meteo best_match", "ncep_nbm_conus" => "NBM",
            "wisp_2026" => "WISP 2026 (NBM, best_match; Open-Meteo ET0)",
            "wisp" => "WISP corrected (FAO-56 ET0, corrected shortwave)"}.freeze

  def initialize(comparison) = @comparison = comparison

  def markdown
    stats = @comparison.stats
    balances = @comparison.balances
    points = balances.keys.map(&:first).uniq
    years = balances.keys.map(&:last).uniq

    <<~MD
      # AgWeather vs Open-Meteo

      Generated #{Date.current} by `bin/rails weather:compare` (PLAN.md §8.4, §8.5). #{points.size} points × #{years.join(", ")} seasons (Apr 1 – Sep 30), daily values from AgWeather (legacy WISP's source) and from Open-Meteo's historical-forecast API at each point's O1280 cell. Points: #{points.join(", ")}.

      Sources: each Open-Meteo model alone with Open-Meteo's own ET0; **WISP 2026**, NBM then best_match hour by hour with Open-Meteo's ET0 (what WISP used through the 2026 season); and **WISP corrected**, the same hours with the shortwave and humidity corrections and WISP's FAO-56 ET0 (D12, what WISP uses from 2027). Precipitation isn't corrected, so the two WISP rows share it.

      Errors are the source minus AgWeather, in inches per day, over days where both have a value.

      ## Reference ET

      #{table(stats[:et0], %i[days reference_mean mean bias ratio mae rmse r])}

      Ratio to AgWeather's ET by month:

      #{month_table(@comparison.et0_by_month)}

      ## Precipitation

      #{table(stats[:precip], %i[days reference_mean mean bias ratio mae rmse r rain_days_reference rain_days rain_day_agreement])}

      Rain days: days with at least #{Weather::Comparison::RAIN_DAY_IN} in; agreement is the share of days where both sources agree on wet or dry.

      ## Effect on a standard field

      A potato field on sand (FC 0.15, PWP 0.05, 16 in roots, MAD 0.5, emergence May 20, full cover by July 1) run through the WISP 3 engine on each source's weather, irrigated #{Weather::Comparison::IRRIGATION_IN} in the day after AD reaches 0. Irrigations per season (first irrigation date):

      #{balance_table(balances)}

      #{balance_summary(balances)}
    MD
  end

  private

  def table(by_source, columns)
    header = "| Model | #{columns.map { |c| c.to_s.tr("_", " ") }.join(" | ")} |"
    rows = by_source.map do |source, s|
      "| #{LABELS.fetch(source, source)} | #{columns.map { |c| format_value(s[c], c) }.join(" | ")} |"
    end
    [header, "|---" * (columns.size + 1) + "|", *rows].join("\n")
  end

  def month_table(by_source)
    months = by_source.values.first.keys
    header = "| Source | #{months.map { Date::ABBR_MONTHNAMES[it] }.join(" | ")} |"
    rows = by_source.map { |source, ratios| "| #{LABELS.fetch(source, source)} | #{ratios.values.map { it ? format("%.2f", it) : "—" }.join(" | ")} |" }
    [header, "|---" * (months.size + 1) + "|", *rows].join("\n")
  end

  def format_value(value, column)
    case value
    when nil then "—"
    when Integer then value.to_s
    else
      (column.to_s.include?("agreement") || column == :ratio || column == :r) ? format("%.2f", value) : format("%.3f", value)
    end
  end

  def balance_table(balances)
    sources = balances.values.first.keys
    header = "| Point | Year | #{sources.map { LABELS.fetch(it, it) }.join(" | ")} |"
    rows = balances.map do |(name, year), by_source|
      "| #{name} | #{year} | #{sources.map { |s|
        r = by_source[s]
        "#{r[:count]} (#{r[:first]&.strftime("%b %-d") || "—"})"
      }.join(" | ")} |"
    end
    [header, "|---" * (sources.size + 2) + "|", *rows].join("\n")
  end

  def balance_summary(balances)
    sources = balances.values.first.keys - ["agweather"]
    lines = sources.map do |source|
      diffs = balances.values.map { |b| b[source][:count] - b["agweather"][:count] }
      shifts = balances.values.filter_map { |b| (b[source][:first] - b["agweather"][:first]).to_i if b[source][:first] && b["agweather"][:first] }
      "- **#{LABELS.fetch(source)}**: #{format("%+.1f", diffs.sum.fdiv(diffs.size))} irrigations per season on average " \
        "(range #{diffs.min} to #{diffs.max}); first irrigation #{shifts.empty? ? "—" : format("%+.1f days", shifts.sum.fdiv(shifts.size))} vs AgWeather."
    end
    shift = balances.values.map { |b| b["wisp"][:count] - b["wisp_2026"][:count] } if sources.include?("wisp")
    correction = shift && "\n\nThe correction itself (WISP corrected minus WISP 2026): #{format("%+.1f", shift.sum.fdiv(shift.size))} irrigations per season on average (range #{shift.min} to #{shift.max})."
    "Average difference from AgWeather:\n\n#{lines.join("\n")}#{correction}"
  end
end

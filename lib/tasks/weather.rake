namespace :weather do
  desc "Compare AgWeather with Open-Meteo models (PLAN.md §8.4) and write docs/weather-comparison.md. " \
    "POINTS=file.csv (name,lat,lng; default: Wisconsin irrigated areas), YEARS=2025,2026"
  task compare: :environment do
    points = if ENV["POINTS"]
      CSV.read(ENV["POINTS"], headers: true).map { |row| [row["name"], Float(row["lat"]), Float(row["lng"])] }
    else
      Weather::Comparison::DEFAULT_POINTS
    end
    years = ENV.fetch("YEARS", "2025,2026").split(",").map { Integer(it) }
    comparison = Weather::Comparison.new(points:, years:, log: ->(message) { warn "  #{message}" })
    path = Rails.root.join("docs/weather-comparison.md")
    File.write(path, WeatherComparisonReport.new(comparison).markdown)
    puts "Wrote #{path.relative_path_from(Rails.root)}"
  end

  desc "Refresh weather for active cells now (as the 3x-daily job does)"
  task refresh: :environment do
    WeatherRefreshJob.perform_now
    WeatherCell.active.each { |cell| WeatherBackfillJob.perform_now(cell.id) }
    puts "Refreshed #{WeatherCell.active.count} cells"
  end
  desc "Refetch stored weather through the current corrections (PLAN.md Phase 8 E): counts the days and " \
    "Open-Meteo calls; CONFIRM=yes queues a job per cell with a pivot"
  task recorrect: :environment do
    fetcher = Weather::Fetcher.new
    # Cells with any stored day not on the current corrections, the last week's included
    plan = WeatherCell.with_pivots.order(:id).filter_map do |cell|
      next unless fetcher.stale_days(cell).exists?
      [cell, fetcher.recorrect_runs(cell).sum(&:size), fetcher.recorrect_calls(cell)]
    end
    days, calls = plan.sum { |_, d, _| d }, plan.sum { |_, _, c| c }
    refresh = plan.size * (Weather::Fetcher::PAST_DAYS + Weather::Fetcher::FORECAST_DAYS).then do |d|
      Weather::OpenMeteo.primary_models.size * Weather::RateLimiter.weight(locations: 1, variables: Weather::OpenMeteo::VARIABLES.size, days: d) +
        Weather::RateLimiter.weight(locations: 1, variables: Weather::OpenMeteo::SOIL_VARIABLES.size, days: d)
    end
    calls += refresh # each job ends with a refresh of the last week and the forecast
    puts "#{plan.size} cells, #{days} days to refetch, about #{calls.round} Open-Meteo calls " \
      "(#{Weather::OpenMeteo.new.mode} API)"
    if ENV["CONFIRM"] == "yes"
      plan.each { |cell, _, _| WeatherRecorrectJob.perform_later(cell.id) }
      puts "Queued #{plan.size} jobs on the weather queue"
    elsif plan.any?
      puts "Run again with CONFIRM=yes to queue them"
    end
  end
end

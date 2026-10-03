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
end

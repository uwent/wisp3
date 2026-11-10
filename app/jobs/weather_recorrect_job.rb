# Refetches a cell's stored days through the current weather corrections (PLAN.md Phase 8 E, step
# 10; bin/rails weather:recorrect). One job per cell, so the rate limiter paces them and a failure
# retries only its cell; a rerun picks up only the days still not current. Then a refresh, for the
# last week and the forecast: the scheduled refresh skips cells without an active season, so
# without it their last stored week would stay uncorrected.
class WeatherRecorrectJob < WeatherJob
  def perform(cell_id)
    cell = WeatherCell.find_by(id: cell_id) or return
    fetcher = Weather::Fetcher.new
    fetcher.recorrect(cell)
    fetcher.refresh([cell])
  end
end

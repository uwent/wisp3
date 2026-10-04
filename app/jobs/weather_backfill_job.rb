# Fills a cell's missing days from its season start (or the last 30 days) through yesterday.
# Runs after each refresh; does nothing when there are no gaps.
class WeatherBackfillJob < WeatherJob
  def perform(cell_id)
    cell = WeatherCell.find_by(id: cell_id) or return
    Weather::Fetcher.new.backfill(cell, from: cell.backfill_start)
  end
end

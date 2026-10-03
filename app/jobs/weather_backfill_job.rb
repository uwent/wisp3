# Fills a cell's missing days from its season start (or the last 30 days) through yesterday.
# Runs when a pivot gets a new cell, and after each refresh; does nothing when there are no gaps.
class WeatherBackfillJob < WeatherJob
  def perform(cell_id)
    cell = WeatherCell.find_by(id: cell_id) or return
    from = [cell.season_start, cell.today - 30].compact.min
    Weather::Fetcher.new.backfill(cell, from:)
  end
end

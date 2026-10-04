# Three times a day: the last week and the 16-day forecast for every active cell, then a backfill
# for any cell with gaps since its season started. all: true (the admin page's "Refresh now")
# covers every cell with a pivot.
class WeatherRefreshJob < WeatherJob
  def perform(all: false)
    cells = (all ? WeatherCell.with_pivots : WeatherCell.active).to_a
    Weather::Fetcher.new.refresh(cells)
    cells.each { |cell| WeatherBackfillJob.perform_later(cell.id) }
  end
end

# Three times a day: the last week, the 16-day forecast and the ensemble for every active cell,
# then a backfill for any cell with gaps since its season started. all: true (the admin page's "Refresh now")
# covers every cell with a pivot.
class WeatherRefreshJob < WeatherJob
  def perform(all: false)
    cells = (all ? WeatherCell.with_pivots : WeatherCell.active).to_a
    fetcher = Weather::Fetcher.new
    fetcher.refresh(cells)
    fetcher.refresh_ensemble(cells)
    cells.each { |cell| WeatherBackfillJob.perform_later(cell.id) }
  end
end

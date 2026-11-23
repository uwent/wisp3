# Three times a day: the last week, the 16-day forecast and the ensemble for every active cell,
# then a backfill for any cell with gaps since its season started, and normals for any cell without
# them (WeatherNormalsJob). all: true (the admin page's "Refresh now")
# covers every cell with a system.
class WeatherRefreshJob < WeatherJob
  def perform(all: false)
    cells = (all ? WeatherCell.with_systems : WeatherCell.active).to_a
    fetcher = Weather::Fetcher.new
    fetcher.refresh(cells)
    fetcher.refresh_ensemble(cells)
    cells.each { |cell| WeatherBackfillJob.perform_later(cell.id) }
    WeatherCell.without_normals(cells.map(&:id)).each { |cell| WeatherNormalsJob.perform_later(cell.id) }
  end
end

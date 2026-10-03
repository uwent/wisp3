# Three times a day: the last week and the 16-day forecast for every active cell, then a backfill
# for any cell with gaps since its season started
class WeatherRefreshJob < WeatherJob
  def perform
    cells = WeatherCell.active.to_a
    Weather::Fetcher.new.refresh(cells)
    cells.each { |cell| WeatherBackfillJob.perform_later(cell.id) }
  end
end

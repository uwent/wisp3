# Brings one cell up to date without waiting for the scheduled refresh: the last week and a new
# forecast if its forecast is stale (WeatherForecast::STALE_AFTER), a new ensemble likewise, then
# any gaps since its season start. Queued when a pivot gets a new cell and when someone opens a page showing the cell's
# pivots (WeatherCell.keep_current); active or not, since a new pivot has no planting yet.
class WeatherUpdateJob < WeatherJob
  def perform(cell_id)
    cell = WeatherCell.find_by(id: cell_id) or return
    fetcher = Weather::Fetcher.new
    fetcher.refresh([cell]) if cell.forecast_stale?
    fetcher.refresh_ensemble([cell]) if cell.forecast_stale?(kind: "ensemble")
    fetcher.backfill(cell, from: cell.backfill_start)
  end
end

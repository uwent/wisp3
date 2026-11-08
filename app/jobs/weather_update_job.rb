# Brings one cell up to date without waiting for the scheduled refresh: the last week and a new
# forecast if its forecast is stale (WeatherForecast::STALE_AFTER), a new ensemble likewise, then
# any gaps since its season start. Queued when a pivot gets a new cell and when someone opens a page showing the cell's
# pivots (WeatherCell.keep_current); active or not, since a new pivot has no planting yet.
#
# While one is queued or running, its cell is marked as updating (WeatherCell.updating_ids), so pages
# showing the cell reload until the weather lands. A retry is enqueued after the failed run's ensure,
# so the mark comes back while it waits; it expires on its own in case a process dies mid-job.
class WeatherUpdateJob < WeatherJob
  UPDATING_FOR = 15.minutes

  def self.updating_key(cell_id) = "weather-updating:#{cell_id}"

  after_enqueue { Rails.cache.write(self.class.updating_key(arguments.first), true, expires_in: UPDATING_FOR) }
  around_perform do |job, block|
    block.call
  ensure
    Rails.cache.delete(self.class.updating_key(job.arguments.first))
  end

  def perform(cell_id)
    cell = WeatherCell.find_by(id: cell_id) or return
    fetcher = Weather::Fetcher.new
    fetcher.refresh([cell]) if cell.forecast_stale?
    fetcher.refresh_ensemble([cell]) if cell.forecast_stale?(kind: "ensemble")
    fetcher.backfill(cell, from: cell.backfill_start)
  end
end

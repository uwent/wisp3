# An O1280 grid cell (Weather::Grid). Pivots in a cell share its daily weather and forecasts.
class WeatherCell < ApplicationRecord
  # Pages ask for an update at most this often per cell
  UPDATE_THROTTLE = 15.minutes
  # A cell whose latest forecast is older than this is incomplete: pages say they're updating it
  # (a forecast newer than this but past WeatherForecast::STALE_AFTER is refreshed quietly)
  INCOMPLETE_AFTER = 1.day

  has_many :pivots, dependent: :nullify
  has_many :plantings, dependent: :nullify
  has_many :weather_days, dependent: :delete_all
  has_many :weather_forecasts, dependent: :delete_all

  validates :latitude, :longitude, presence: true

  def self.for(latitude, longitude)
    cell = Weather::Grid.cell_for(latitude, longitude)
    find_or_create_by!(latitude: cell.latitude.round(6), longitude: cell.longitude.round(6))
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # Cells with a planting this season (or one still running), and cells whose weather a daily
  # digest shows out of season. A planting's cell is its pivot's, or where its pivot was (G.9).
  def self.active(today = Date.current)
    planted = Planting.where("end_date >= ? OR season_start >= ?", today, today.beginning_of_year)
      .where.not(weather_cell_id: nil).select(:weather_cell_id)
    where(id: planted).or(where(id: digest_cell_ids))
  end

  # Cells of the pivots in digests that list fields out of season too (every included field, or
  # every morning all year)
  def self.digest_cell_ids
    User.where.not(digest_frequency: "never").where.not(confirmed_at: nil)
      .where("digest_scope = 'all' OR digest_frequency = 'daily_all_year'")
      .flat_map { |user| user.digest_fields.joins(:pivot).distinct.pluck("pivots.weather_cell_id") }.uniq
  end

  # Cells with a pivot (inactive ones too), for a refresh asked for by hand
  def self.with_pivots = where(id: Pivot.select(:weather_cell_id))

  # Queues a WeatherUpdateJob for each cell, at most once per UPDATE_THROTTLE. Pages showing
  # pivots call this, so the cells people look at stay current between scheduled refreshes, even
  # before they have a planting. Only an incomplete cell's update is shown on the pages ("Updating
  # weather…", reloading until it lands); a complete one's is quiet, and the next visit gets it.
  def self.keep_current(ids)
    due = ids.compact.uniq.select do |id|
      Rails.cache.write("weather-update:#{id}", true, unless_exist: true, expires_in: UPDATE_THROTTLE)
    end
    where(id: due).find_each { |cell| WeatherUpdateJob.perform_later(cell.id, quiet: !cell.incomplete?) }
  end

  # Of these cells, the ones with a WeatherUpdateJob queued or running
  def self.updating_ids(ids)
    ids = ids.compact.uniq
    keys = ids.index_by { |id| WeatherUpdateJob.updating_key(id) }
    Rails.cache.read_multi(*keys.keys).keys.map { |key| keys[key] }
  end

  # kind: "deterministic" or "ensemble"
  def forecast_stale?(now = Time.current, kind: "deterministic")
    issued = weather_forecasts.where(kind:).maximum(:issued_at)
    issued.nil? || issued < now - WeatherForecast::STALE_AFTER
  end

  # Missing weather the balances would use: no forecast within INCOMPLETE_AFTER, or a day missing
  # since the earliest season start this year, or 30 days back. Earlier days of the year (for the
  # weather page) fill in quietly.
  def incomplete?(now = Time.current)
    issued = weather_forecasts.deterministic.maximum(:issued_at)
    return true if issued.nil? || issued < now - INCOMPLETE_AFTER
    from, to = [season_start, today - 30].compact.min, today - 1
    from <= to && weather_days.where(date: from..to).count < (to - from).to_i + 1
  end

  # Backfills start on January 1, so a weather zone's page has the whole year (G.12), or at the
  # earliest season start this year if it began the year before
  def backfill_start = [season_start, today.beginning_of_year].compact.min

  # Open-Meteo gives elevation in meters; growers see feet
  def elevation_ft = elevation_m && (elevation_m / 0.3048).round

  def time_zone = ActiveSupport::TimeZone[timezone || Time.zone.name]
  def today = Time.current.in_time_zone(time_zone).to_date

  def latest_forecast = weather_forecasts.deterministic.order(issued_at: :desc).first
  def latest_ensemble = weather_forecasts.ensemble.order(issued_at: :desc).first

  # Earliest season start of this cell's plantings this year, for backfills
  def season_start(today = self.today)
    Planting.where(weather_cell_id: id).where("end_date >= ?", today.beginning_of_year).minimum(:season_start)
  end
end

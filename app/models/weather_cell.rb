# An O1280 grid cell (Weather::Grid). Pivots in a cell share its daily weather and forecasts.
class WeatherCell < ApplicationRecord
  has_many :pivots, dependent: :nullify
  has_many :weather_days, dependent: :delete_all
  has_many :weather_forecasts, dependent: :delete_all

  validates :latitude, :longitude, presence: true

  def self.for(latitude, longitude)
    cell = Weather::Grid.cell_for(latitude, longitude)
    find_or_create_by!(latitude: cell.latitude.round(6), longitude: cell.longitude.round(6))
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  # Cells with a pivot whose fields have a planting this season (or one still running)
  def self.active(today = Date.current)
    where(id: Pivot.joins(fields: :plantings)
      .where("plantings.end_date >= ? OR plantings.season_start >= ?", today, today.beginning_of_year)
      .select(:weather_cell_id))
  end

  def time_zone = ActiveSupport::TimeZone[timezone || Time.zone.name]
  def today = Time.current.in_time_zone(time_zone).to_date

  def latest_forecast = weather_forecasts.order(issued_at: :desc).first

  # Earliest season start of this cell's plantings this year, for backfills
  def season_start(today = self.today)
    Planting.joins(field: :pivot).where(pivots: {weather_cell_id: id})
      .where("plantings.end_date >= ?", today.beginning_of_year).minimum(:season_start)
  end
end

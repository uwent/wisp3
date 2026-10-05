# One forecast issue for a cell. The latest few issues of each kind are kept (ForecastPruneJob).
# - deterministic: payload["days"] holds daily values with the same keys as
#   WeatherDay::VALUE_COLUMNS, plus "date".
# - ensemble (Weather::Ensemble): payload["dates"] and payload["members"], each member
#   {"et0_in" => [...], "precip_in" => [...]} by date.
class WeatherForecast < ApplicationRecord
  KEEP = 14
  # A forecast older than this is refetched when someone opens a page showing the cell's pivots
  STALE_AFTER = 3.hours

  scope :deterministic, -> { where(kind: "deterministic") }
  scope :ensemble, -> { where(kind: "ensemble") }

  # The latest issue of each cell's forecasts in this scope
  def self.latest_by_cell(cell_ids)
    where(weather_cell_id: cell_ids).select("DISTINCT ON (weather_cell_id) *").order(:weather_cell_id, issued_at: :desc)
      .index_by(&:weather_cell_id)
  end

  belongs_to :weather_cell

  validates :issued_at, :model, :payload, presence: true
  validates :kind, inclusion: {in: %w[deterministic ensemble]}

  # {date => {"et0_in" => …, …}} (deterministic)
  def days = payload.fetch("days").to_h { |day| [Date.parse(day["date"]), day.except("date")] }

  # Each member's {date => {et0:, precip:}} (ensemble)
  def members
    dates = payload.fetch("dates").map { |date| Date.parse(date) }
    payload.fetch("members").map do |member|
      dates.each_with_index.to_h { |date, i| [date, {et0: member["et0_in"][i], precip: member["precip_in"][i]}] }
    end
  end
end

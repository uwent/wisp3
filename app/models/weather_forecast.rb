# One forecast issue for a cell. payload["days"] holds daily values with the same keys as
# WeatherDay::VALUE_COLUMNS, plus "date". The latest few issues are kept (ForecastPruneJob).
class WeatherForecast < ApplicationRecord
  KEEP = 14

  belongs_to :weather_cell

  validates :issued_at, :model, :payload, presence: true
  validates :kind, inclusion: {in: %w[deterministic ensemble]}

  # {date => {"et0_in" => …, …}}
  def days = payload.fetch("days").to_h { |day| [Date.parse(day["date"]), day.except("date")] }
end

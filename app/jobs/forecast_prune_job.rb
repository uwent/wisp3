# Weekly: keep each cell's latest WeatherForecast::KEEP forecasts of each kind (older ones are only useful for
# checking forecast accuracy, which needs a handful)
class ForecastPruneJob < WeatherJob
  def perform
    WeatherForecast.where(<<~SQL.squish, keep: WeatherForecast::KEEP).delete_all
      id IN (SELECT id FROM (
        SELECT id, row_number() OVER (PARTITION BY weather_cell_id, kind ORDER BY issued_at DESC) AS rank
        FROM weather_forecasts) ranked WHERE rank > :keep)
    SQL
  end
end

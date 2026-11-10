# Weekly: keep each cell's latest WeatherForecast::KEEP forecasts of each kind, and for good, the daily
# archive (PLAN.md Phase 8 E): each cell's first corrected issue of each kind on each local day,
# for forecast accuracy tracking and time travel's replay. Only corrected issues are archived
# (the deterministic days list their corrections; the ensemble's payload has "corrections"), so the
# archive starts on one method.
class ForecastPruneJob < WeatherJob
  DEFAULT_TIMEZONE = "America/Chicago"

  def perform
    WeatherForecast.where(<<~SQL.squish, keep: WeatherForecast::KEEP, zone: DEFAULT_TIMEZONE).delete_all
      id IN (SELECT id FROM (
        SELECT f.id,
          row_number() OVER (PARTITION BY f.weather_cell_id, f.kind ORDER BY f.issued_at DESC) AS rank,
          corrected,
          row_number() OVER (
            PARTITION BY f.weather_cell_id, f.kind, (f.issued_at AT TIME ZONE COALESCE(c.timezone, :zone))::date
            ORDER BY corrected DESC, f.issued_at) AS daily_rank
        FROM weather_forecasts f
        JOIN weather_cells c ON c.id = f.weather_cell_id
        CROSS JOIN LATERAL (SELECT CASE WHEN f.kind = 'ensemble' THEN jsonb_exists(f.payload, 'corrections')
          ELSE COALESCE(jsonb_array_length(f.payload -> 'days' -> 0 -> 'corrections'), 0) > 0 END AS corrected) k
      ) ranked WHERE rank > :keep AND NOT (daily_rank = 1 AND corrected))
    SQL
  end
end

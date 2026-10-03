class WeatherCellStatusSerializer < ApplicationSerializer
  attributes :id, :latitude, :longitude, :timezone, :elevation_m, :pivot_count, :active, :season_start, :days_stored,
    :missing_days, :provisional_days, :latest_date, :forecast_issued_at, :forecast_through, :last_fetched_at,
    :last_error, :last_error_at

  typelize id: :number, latitude: :number, longitude: :number, timezone: "string | null",
    elevation_m: "number | null", pivot_count: :number, active: :boolean, season_start: "string | null",
    days_stored: :number, missing_days: "number | null", provisional_days: :number, latest_date: "string | null",
    forecast_issued_at: "string | null", forecast_through: "string | null", last_fetched_at: "string | null",
    last_error: "string | null", last_error_at: "string | null"
end

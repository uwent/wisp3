# One row of the admin weather-status page: a cell's coverage this season, latest forecast, and
# fetch errors. Built in a handful of grouped queries rather than per cell.
WeatherCellStatus = Data.define(:id, :latitude, :longitude, :timezone, :elevation_m, :pivot_count, :active,
  :season_start, :days_stored, :missing_days, :provisional_days, :latest_date, :forecast_issued_at,
  :forecast_through, :last_fetched_at, :last_error, :last_error_at) do
  def self.all
    cells = WeatherCell.order(:id).to_a
    active = WeatherCell.active.pluck(:id).to_set
    pivots = Pivot.group(:weather_cell_id).count
    year_start = Date.current.beginning_of_year
    days = WeatherDay.where(date: year_start..).group(:weather_cell_id)
      .pluck(:weather_cell_id, Arel.sql("count(*)"), Arel.sql("count(*) FILTER (WHERE NOT final)"), Arel.sql("max(date)"))
      .to_h { |id, *rest| [id, rest] }
    forecasts = WeatherForecast.select("DISTINCT ON (weather_cell_id) weather_cell_id, issued_at, payload")
      .order(:weather_cell_id, issued_at: :desc).index_by(&:weather_cell_id)

    cells.map do |cell|
      count, provisional, latest = days[cell.id] || [0, 0, nil]
      season_start = cell.season_start
      expected = season_start ? (cell.today - season_start).to_i : nil
      stored_in_season = season_start ? cell.weather_days.where(date: season_start...cell.today).count : nil
      forecast = forecasts[cell.id]
      new(id: cell.id, latitude: cell.latitude, longitude: cell.longitude, timezone: cell.timezone,
        elevation_m: cell.elevation_m, pivot_count: pivots.fetch(cell.id, 0), active: active.include?(cell.id),
        season_start:, days_stored: count, missing_days: expected && [expected - stored_in_season, 0].max,
        provisional_days: provisional, latest_date: latest, forecast_issued_at: forecast&.issued_at,
        forecast_through: forecast&.payload&.dig("days")&.last&.dig("date"), last_fetched_at: cell.last_fetched_at,
        last_error: cell.last_error, last_error_at: cell.last_error_at)
    end
  end
end

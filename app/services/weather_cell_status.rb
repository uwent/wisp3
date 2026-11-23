# One row of the admin weather-status page: a cell's coverage this season, latest forecast, and
# fetch errors. Built in a handful of grouped queries rather than per cell.
WeatherCellStatus = Data.define(:id, :latitude, :longitude, :timezone, :elevation_m, :system_count, :active,
  :season_start, :days_stored, :missing_days, :provisional_days, :latest_date, :forecast_issued_at,
  :forecast_through, :last_fetched_at, :last_error, :last_error_at) do
  def self.all
    cells = WeatherCell.order(:id).to_a
    active = WeatherCell.active.pluck(:id).to_set
    systems = IrrigationSystem.group(:weather_cell_id).count
    year_start = Date.current.beginning_of_year
    days = WeatherDay.where(date: year_start..).group(:weather_cell_id)
      .pluck(:weather_cell_id, Arel.sql("count(*)"), Arel.sql("count(*) FILTER (WHERE NOT final)"), Arel.sql("max(date)"))
      .to_h { |id, *rest| [id, rest] }
    forecasts = WeatherForecast.deterministic.latest_by_cell(cells.map(&:id))
    todays = cells.to_h { |cell| [cell.id, cell.today] }
    season_starts = season_starts(todays)
    stored = stored_in_season(season_starts, todays)

    cells.map do |cell|
      count, provisional, latest = days[cell.id] || [0, 0, nil]
      season_start = season_starts[cell.id]
      expected = season_start ? (todays[cell.id] - season_start).to_i : nil
      stored_in_season = season_start ? stored.fetch(cell.id, 0) : nil
      forecast = forecasts[cell.id]
      new(id: cell.id, latitude: cell.latitude, longitude: cell.longitude, timezone: cell.timezone,
        elevation_m: cell.elevation_m, system_count: systems.fetch(cell.id, 0), active: active.include?(cell.id),
        season_start:, days_stored: count, missing_days: expected && [expected - stored_in_season, 0].max,
        provisional_days: provisional, latest_date: latest, forecast_issued_at: forecast&.issued_at,
        forecast_through: forecast&.payload&.dig("days")&.last&.dig("date"), last_fetched_at: cell.last_fetched_at,
        last_error: cell.last_error, last_error_at: cell.last_error_at)
    end
  end

  # {cell id => the earliest season start of its plantings this year} (WeatherCell#season_start),
  # one query per distinct day (the cells' time zones rarely straddle midnight)
  def self.season_starts(todays)
    todays.group_by { |_, today| today.beginning_of_year }.each_with_object({}) do |(year_start, pairs), starts|
      starts.merge!(Planting.where(weather_cell_id: pairs.map(&:first)).where("end_date >= ?", year_start)
        .group(:weather_cell_id).minimum(:season_start))
    end
  end

  # {cell id => its stored days from its season start to before its today}
  def self.stored_in_season(season_starts, todays)
    return {} if season_starts.empty?

    rows = season_starts.map do |id, start|
      ActiveRecord::Base.sanitize_sql_array(["(?::bigint, ?::date, ?::date)", id, start, todays.fetch(id)])
    end
    WeatherDay.joins("JOIN (VALUES #{rows.join(", ")}) AS seasons(cell_id, starts, today) " \
      "ON seasons.cell_id = weather_days.weather_cell_id")
      .where("weather_days.date >= seasons.starts AND weather_days.date < seasons.today")
      .group(:weather_cell_id).count
  end
end

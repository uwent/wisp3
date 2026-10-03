module Weather
  # Fetches weather for cells and stores it (PLAN.md §8.3): past days as WeatherDay rows
  # (provisional until finalized; final days are never overwritten), today onward as a
  # WeatherForecast. Errors are recorded on the cells for the admin status page, then re-raised
  # for the job to retry.
  class Fetcher
    PAST_DAYS = 7
    FORECAST_DAYS = 16
    BACKFILL_CHUNK_DAYS = 92

    def initialize(client: OpenMeteo.new, model: OpenMeteo.primary_model)
      @client, @model = client, model
    end

    # The last week and the 16-day forecast
    def refresh(cells)
      cells.each_slice(OpenMeteo::BATCH_SIZE) do |batch|
        fetch(batch, :forecast, past_days: PAST_DAYS, forecast_days: FORECAST_DAYS)
      end
    end

    # Fills days missing from `from` through yesterday, from the historical-forecast API (the same
    # models as the forecast, so the series stays consistent). Returns the number of days stored.
    def backfill(cell, from:, to: cell.today - 1)
      missing_runs(cell, from, to).sum do |run|
        run.each_slice(BACKFILL_CHUNK_DAYS).sum do |chunk|
          fetch([cell], :historical_forecast, start_date: chunk.first, end_date: chunk.last)
        end
      end
    end

    # Runs of consecutive dates in from..to with no stored day
    def missing_runs(cell, from, to)
      return [] if from > to
      have = cell.weather_days.where(date: from..to).pluck(:date).to_set
      (from..to).reject { |date| have.include?(date) }.slice_when { |a, b| b != a + 1 }.to_a
    end

    private

    def fetch(cells, endpoint, **dates)
      locations = cells.map { |cell| [cell.latitude, cell.longitude] }
      primary = @client.hourly(locations, endpoint:, model: @model, variables: OpenMeteo::VARIABLES, **dates)
      soil = @client.hourly(locations, endpoint:, model: OpenMeteo::SOIL_MODEL, variables: OpenMeteo::SOIL_VARIABLES,
        **dates)
      cells.zip(primary, soil).sum do |cell, primary_hours, soil_hours|
        store(cell, primary_hours, Daily.from_hourly(primary_hours, soil_hours), forecast: endpoint == :forecast)
      end
    rescue Error => e
      WeatherCell.where(id: cells.map(&:id)).update_all(last_error: e.message, last_error_at: Time.current)
      raise
    end

    def store(cell, response, days, forecast:)
      now = Time.current
      cell.update!(timezone: response.timezone, elevation_m: response.elevation, last_fetched_at: now, last_error: nil)
      today = cell.today

      past = days.select { |date, day| date < today && day["hours"] >= 24 - Daily::MAX_MISSING_HOURS }
      final = cell.weather_days.where(final: true, date: past.keys).pluck(:date).to_set
      rows = past.except(*final).map do |date, day|
        WeatherDay::VALUE_COLUMNS.index_with { |column| day[column] }.merge(
          weather_cell_id: cell.id, date:, model: @model, soil_model: OpenMeteo::SOIL_MODEL, hours: day["hours"],
          fetched_at: now, final: false
        )
      end
      WeatherDay.upsert_all(rows, unique_by: [:weather_cell_id, :date]) if rows.any?

      if forecast
        upcoming = days.select { |date, _| date >= today }.sort.map { |date, day| day.except("hours").merge("date" => date.iso8601) }
        cell.weather_forecasts.create!(issued_at: now, model: @model, payload: {"days" => upcoming}) if upcoming.any?
      end
      rows.size
    end
  end
end

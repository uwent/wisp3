module Weather
  # A cell's daily temperature normals (WeatherNormal), for canopy curves in thermal time
  # (C23): the mean high and low on each day of the year over the last YEARS complete years of
  # Open-Meteo's historical archive (ERA5, with ERA5-Land's 0.1° grid where it has it), smoothed
  # with a WINDOW-day moving average so one odd year doesn't put a step in the curve. One request
  # per cell, fetched once (WeatherNormalsJob).
  class Normals
    YEARS = 20
    MODEL = "era5_seamless"
    VARIABLES = %w[temperature_2m_max temperature_2m_min].freeze
    WINDOW = 15

    def initialize(client: OpenMeteo.new)
      @client = client
    end

    # Fetches and stores the cell's normals from the years complete years before today, replacing any it
    # had. Returns the number of days stored.
    def fetch(cell, today: Date.current, years: YEARS)
      last_year = today.year - 1
      first_year = last_year - years + 1
      response = @client.daily([cell.latitude, cell.longitude], endpoint: :archive, model: MODEL, variables: VARIABLES,
        start_date: Date.new(first_year, 1, 1), end_date: Date.new(last_year, 12, 31))
      normals = self.class.compute(response.dates, *response.values.values_at(*VARIABLES))
      now = Time.current
      rows = normals.map do |day_of_year, (tmax_f, tmin_f)|
        {weather_cell_id: cell.id, day_of_year:, tmax_f:, tmin_f:, first_year:, last_year:, model: MODEL,
         fetched_at: now, created_at: now, updated_at: now}
      end
      WeatherNormal.transaction do
        WeatherNormal.where(weather_cell_id: cell.id).delete_all
        WeatherNormal.insert_all!(rows)
      end
      rows.size
    end

    # {day_of_year => [tmax_f, tmin_f]} for days 1..366 (as in a leap year) from daily highs and lows
    # in °C (nil where missing): each day's mean over the years, then a centered WINDOW-day moving
    # average around the year (Feb 29, in a quarter of the years, comes out like its neighbors)
    def self.compute(dates, highs, lows)
      sums = Array.new(367) { [0.0, 0.0, 0] }
      dates.each_with_index do |date, i|
        next if highs[i].nil? || lows[i].nil?
        sum = sums[WeatherNormal.day_of_year(date)]
        sum[0] += highs[i]
        sum[1] += lows[i]
        sum[2] += 1
      end
      means = (1..366).map { |day| sums[day] }
      raise Error, "Open-Meteo archive: no temperatures" if means.all? { |_, _, n| n.zero? }

      half = WINDOW / 2
      (1..366).to_h do |day|
        # The days around it with values; with none (a gap in the archive), the nearest that has some
        window = (half..183).lazy.map do |reach|
          (-reach..reach).map { |offset| means[(day - 1 + offset) % 366] }.reject { |_, _, n| n.zero? }
        end.find(&:any?)
        high = window.sum { |s, _, n| s / n } / window.size
        low = window.sum { |_, s, n| s / n } / window.size
        [day, [(high * 9 / 5.0 + 32).round(1), (low * 9 / 5.0 + 32).round(1)]]
      end
    end
  end
end

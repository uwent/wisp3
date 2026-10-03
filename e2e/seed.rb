# Data for the browser smoke tests (bin/e2e): the demo account, and synthetic weather for every cell
# from April 1 through today, so pages render with a full season and no network.
EMAIL = "e2e@example.com"
PASSWORD = "e2e-password-1"

ReferenceData.load!
DemoSeed.new(email: EMAIL, password: PASSWORD).run
User.find_by!(email: EMAIL).update!(password: PASSWORD)

today = Date.current
now = Time.current
WeatherCell.find_each do |cell|
  rows = (Date.new(today.year, 4, 1)..today).map do |date|
    wave = Math.sin(date.yday / 9.0)
    {weather_cell_id: cell.id, date:, et0_in: (0.12 + 0.06 * wave).round(3), precip_in: (date.yday % 6).zero? ? 0.45 : 0.0,
     tmax_f: (78 + 8 * wave).round(1), tmin_f: (56 + 6 * wave).round(1), rh_mean_pct: 70, wind_speed_mph: 7,
     cloud_cover_pct: 40, model: "e2e", hours: 24, final: date < today - 5, fetched_at: now, created_at: now, updated_at: now}
  end
  WeatherDay.upsert_all(rows, unique_by: %i[weather_cell_id date])
end

puts "e2e: #{EMAIL}, #{WeatherCell.count} cells with weather through #{today}"

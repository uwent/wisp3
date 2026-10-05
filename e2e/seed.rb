# Data for the browser smoke tests (bin/e2e): the demo account, and synthetic weather for every cell
# from April 1 through today, so pages render with a full season and no network.
EMAIL = "e2e@example.com"
PASSWORD = "e2e-password-1"

ReferenceData.load!
DemoSeed.new(email: EMAIL, password: PASSWORD).run
# An admin, so the smoke tests cover the admin pages
User.find_by!(email: EMAIL).update!(password: PASSWORD, admin: true)

today = Date.current
now = Time.current

# Keep the first field's season (the dashboard's first card, which the tests open) running past
# today, so it has a projection whenever the tests run between April and the fall
Planting.joins(:plant).where(plants: {key: "cabbage"}).find_each do |planting|
  planting.update!(end_date: [planting.end_date, today + 30].max)
end
WeatherCell.find_each do |cell|
  rows = (Date.new(today.year, 4, 1)..today).map do |date|
    wave = Math.sin(date.yday / 9.0)
    {weather_cell_id: cell.id, date:, et0_in: (0.12 + 0.06 * wave).round(3), precip_in: (date.yday % 6).zero? ? 0.45 : 0.0, rain_in: (date.yday % 6).zero? ? 0.45 : 0.0,
     tmax_f: (78 + 8 * wave).round(1), tmin_f: (56 + 6 * wave).round(1), rh_mean_pct: 70, wind_speed_mph: 7,
     cloud_cover_pct: 40, model: "e2e", hours: 24, final: date < today - 5, fetched_at: now, created_at: now, updated_at: now}
  end
  WeatherDay.upsert_all(rows, unique_by: %i[weather_cell_id date])

  # The forecast from today, and an ensemble of 31 members spread around it
  ahead = (today..today + 15).to_a
  cell.weather_forecasts.delete_all
  cell.weather_forecasts.create!(issued_at: now, model: "e2e", payload: {days: ahead.map do |date|
    {date: date.iso8601, et0_in: 0.2, precip_in: (date == today + 6) ? 0.6 : 0.0, tmax_f: 84, tmin_f: 60}
  end})
  cell.weather_forecasts.create!(kind: "ensemble", issued_at: now, model: "e2e", payload: {
    dates: ahead.map(&:iso8601),
    members: (0...31).map do |m|
      {et0_in: ahead.map { 0.14 + 0.004 * m }, precip_in: ahead.map { |date| (date == today + 3 + m % 7) ? 0.02 * m : 0.0 }}
    end
  })
end

puts "e2e: #{EMAIL}, #{WeatherCell.count} cells with weather through #{today}"

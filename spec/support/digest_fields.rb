# Fields in season on 2026-07-20 for daily digest specs: three weeks of weather and a 16-day forecast
# at 0.2 in/day of ET0, and full canopy, so a field's moisture reading on Jul 19 sets how soon it
# needs water (15% is fine for five days, 12% crosses in two, 9% is below the irrigation point).
module DigestFields
  def digest_today = Time.zone.local(2026, 7, 20, 6)

  def digest_weather(pivot)
    cell = pivot.weather_cell
    (Date.new(2026, 7, 1)..Date.new(2026, 7, 19)).each do |date|
      cell.weather_days.create!(date:, et0_in: 0.2, precip_in: 0.0, tmax_f: 85, tmin_f: 60, model: "ncep_nbm_conus",
        hours: 24, fetched_at: Time.current)
    end
    dates = Date.new(2026, 7, 20)..Date.new(2026, 8, 4)
    cell.weather_forecasts.create!(issued_at: Time.current, model: "ncep_nbm_conus",
      payload: {days: dates.map { |date| {date: date.iso8601, et0_in: 0.2, precip_in: 0.0} }})
  end

  def digest_field(pivot, name, moisture_pct)
    field = create(:field, pivot:, name:)
    planting = create(:planting, field:, season_start: Date.new(2026, 7, 1), emergence_date: Date.new(2026, 7, 1),
      end_date: Date.new(2026, 9, 30))
    create(:canopy_observation, planting:, date: Date.new(2026, 7, 1), pct_cover: 90)
    field.field_entries.create!(date: Date.new(2026, 7, 19), soil_moisture_pct: moisture_pct)
    field
  end
end

RSpec.configure { |config| config.include DigestFields }

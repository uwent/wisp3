# A stand-in for Weather::OpenMeteo#hourly in specs: constant weather (10 °C, 0.3 soil moisture,
# et0_mm per hour of Open-Meteo's ET0; a 6 °C dew point, 1000 hPa, 10 km/h wind, and shortwave
# from 6 am to 6 pm) for every requested variable over the local (Chicago) days asked, and a log of
# the calls. From the ensemble endpoint, each of members has the same values as the control.
class FakeOpenMeteo
  attr_reader :calls

  def initialize(today:, et0_mm: 0.2, members: 3) = (@today, @et0_mm, @members, @calls = today, et0_mm, members, [])

  def hourly(locations, endpoint:, model:, variables:, **dates)
    @calls << {endpoint:, model:, locations: locations.size, **dates}
    first, last = dates[:start_date] ? [dates[:start_date], dates[:end_date]] : [@today - dates[:past_days].to_i, @today + dates[:forecast_days] - 1]
    zone = ActiveSupport::TimeZone["America/Chicago"]
    times = (first..last).flat_map { |date| (0..23).map { |h| zone.local(date.year, date.month, date.day, h).utc } }
    locations.map do |lat, lng|
      names = (endpoint == :ensemble) ? variables.flat_map { |v| [v] + (1...@members).map { |n| format("%s_member%02d", v, n) } } : variables
      values = names.to_h { |v| [v, times.map { |time| value(v, time) }] }
      Weather::OpenMeteo::Hourly.new(latitude: lat, longitude: lng, timezone: "America/Chicago", elevation: 300, times:, values:)
    end
  end

  private

  def value(variable, time)
    case variable
    when /\Asoil_moisture/ then 0.3
    when /\Aet0/ then @et0_mm
    when "dew_point_2m" then 6.0
    when "surface_pressure" then 1000.0
    when "shortwave_radiation" then time.in_time_zone("America/Chicago").hour.between?(7, 18) ? 500.0 : 0.0
    else 10.0
    end
  end
end

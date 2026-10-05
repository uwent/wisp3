# A stand-in for Weather::OpenMeteo#hourly in specs: constant weather (10 °C, 0.3 soil moisture,
# et0_mm per hour) for every requested variable over the dates asked, and a log of the calls. From
# the ensemble endpoint, each of members has the same values as the control.
class FakeOpenMeteo
  attr_reader :calls

  def initialize(today:, et0_mm: 0.2, members: 3) = (@today, @et0_mm, @members, @calls = today, et0_mm, members, [])

  def hourly(locations, endpoint:, model:, variables:, **dates)
    @calls << {endpoint:, model:, locations: locations.size, **dates}
    first, last = dates[:start_date] ? [dates[:start_date], dates[:end_date]] : [@today - dates[:past_days].to_i, @today + dates[:forecast_days] - 1]
    times = (first..last).flat_map { |date| (0..23).map { |h| format("%sT%02d:00", date.iso8601, h) } }
    locations.map do |lat, lng|
      names = (endpoint == :ensemble) ? variables.flat_map { |v| [v] + (1...@members).map { |n| format("%s_member%02d", v, n) } } : variables
      values = names.to_h { |v|
        [v, Array.new(times.size) {
          if v.start_with?("soil_moisture")
            0.3
          else
            (v.start_with?("et0") ? @et0_mm : 10.0)
          end
        }]
      }
      Weather::OpenMeteo::Hourly.new(latitude: lat, longitude: lng, timezone: "America/Chicago", elevation: 300, times:, values:)
    end
  end
end

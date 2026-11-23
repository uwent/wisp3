# A weather zone (WeatherZone) on the Map tab: its grid cell's box, its weather in brief over the
# last week and the next (WeatherSummary, params[:weather] by cell id) and the week ahead
# (ForecastDays, params[:forecasts] by cell id). Values as stored (inches, °F); a high or low is
# its range over the span as [lowest, highest].
class MapZoneSerializer < ApplicationSerializer
  attributes :id, :location, :coordinates

  attribute(:bounds) do |zone|
    cell = Weather::Grid.cell_for(zone.cell.latitude, zone.cell.longitude)
    {north: cell.lat_north, south: cell.lat_south, west: cell.lng_west, east: cell.lng_east}
  end

  attribute(:weather) do |zone|
    spans = params[:weather].fetch(zone.id, {})
    {past: span(spans[:past]), ahead: span(spans[:ahead])}
  end

  attribute(:forecast) { |zone| ForecastDaySerializer.new(params[:forecasts].fetch(zone.id, [])).to_h }

  def span(span)
    span && {days: span.days, precip: span.precip, et0: span.et0, tmax: span.tmax && [span.tmax.begin, span.tmax.end],
             tmin: span.tmin && [span.tmin.begin, span.tmin.end]}
  end

  typelize id: :number, location: :string, coordinates: :string,
    bounds: "{ north: number; south: number; west: number; east: number }",
    weather: "import('@/lib/weatherSummary').ZoneWeather",
    forecast: "import('@/types/serializers').ForecastDay[]"
end

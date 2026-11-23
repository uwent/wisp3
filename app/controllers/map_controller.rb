# The map: the dashboard's farms, pivots and field cards, with each pivot's location, its weather
# zone and its fields' outlines, for a season (?year=; this year by default), and the weather zones of
# the operation's systems (as /weather lists them: only those cells are kept current) with their
# weather over the last 7 days and the next 7 and the week ahead.
class MapController < AuthenticatedController
  allow_example :show

  def show
    today = Current.today
    year = requested_year
    overview = OperationOverview.new(Current.group, today:, year:)
    zones = overview.pivots.select(&:weather_cell).group_by(&:weather_cell)
      .map { |cell, pivots| WeatherZone.new(cell, pivots) }.sort_by(&:sort_key)
    cell_ids = zones.map(&:id)

    render inertia: "Map/Show", props: {
      today: overview.today,
      year: overview.year,
      years: overview.years,
      farms: overview.props do |pivot|
        pivot.slice(*PivotSerializer::SHAPE).symbolize_keys.merge(
          weather_cell_id: pivot.weather_cell_id,
          outlines: pivot.fields.select(&:boundary).map { |field| {field_id: field.id, boundary: field.boundary} }
        )
      end,
      zones: MapZoneSerializer.new(zones, params: {
        weather: WeatherSummary.by_cell(cell_ids, today: overview.today),
        forecasts: ForecastDays.by_cell(cell_ids, today: overview.today)
      }).to_h
    }
  end
end

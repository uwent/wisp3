# The map (PLAN.md Phase 7): the dashboard's farms, pivots and field cards, with each pivot's
# location and its weather zone's rain and ET over the last 7 days and the next 7.
class MapController < AuthenticatedController
  def show
    overview = OperationOverview.new(Current.group)
    weather = WeatherSummary.by_cell(overview.pivots.map(&:weather_cell_id).uniq, today: overview.today)

    render inertia: "Map/Show", props: {
      today: overview.today,
      farms: overview.props do |pivot|
        pivot.slice(*PivotSerializer::SHAPE).symbolize_keys.merge(
          weather: weather[pivot.weather_cell_id]&.transform_values { |span| span && totals(span) }
        )
      end
    }
  end

  private

  def totals(span) = {days: span.days, precip: span.precip, et0: span.et0}
end

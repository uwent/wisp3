# The map (PLAN.md Phase 7): the dashboard's farms, pivots and field cards, with each pivot's
# location and its weather zone's rain and ET over the last 7 days and the next 7, and its fields'
# outlines (G.10), for a season (?year=, G.14; this year by default).
class MapController < AuthenticatedController
  def show
    today = Date.current
    year = params[:year].to_i.between?(2000, today.year + 1) ? params[:year].to_i : today.year
    overview = OperationOverview.new(Current.group, today:, year:)
    weather = WeatherSummary.by_cell(overview.pivots.map(&:weather_cell_id).uniq, today: overview.today)

    render inertia: "Map/Show", props: {
      today: overview.today,
      year: overview.year,
      years: overview.years,
      farms: overview.props do |pivot|
        pivot.slice(*PivotSerializer::SHAPE).symbolize_keys.merge(
          weather: weather[pivot.weather_cell_id]&.transform_values { |span| span && totals(span) },
          outlines: pivot.fields.select(&:boundary).map { |field| {field_id: field.id, boundary: field.boundary} }
        )
      end
    }
  end

  private

  def totals(span) = {days: span.days, precip: span.precip, et0: span.et0}
end

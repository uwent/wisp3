# Every field's water status today (PLAN.md §11), by farm and pivot: one card per field with this
# season's planting.
class DashboardController < AuthenticatedController
  allow_example :show

  def show
    overview = OperationOverview.new(Current.group)
    render inertia: "Dashboard/Show", props: {
      today: overview.today, farms: overview.props, getting_started: getting_started(overview),
      rain: rain(overview)
    }
  end

  private

  # The week's rain in each weather zone of the operation's systems, north to south (RainAhead,
  # docs/plans/phase-9.md §9), with its systems (named, and for the farm filter): [{id, name,
  # coordinates, location, systems, pivot_ids, days}]
  def rain(overview)
    zones = overview.pivots.select(&:weather_cell).group_by(&:weather_cell)
      .map { |cell, pivots| WeatherZone.new(cell, pivots) }.sort_by { |zone| [-zone.cell.latitude, zone.cell.longitude] }
    forecasts = ForecastDays.by_cell(zones.map(&:id))
    zones.filter_map do |zone|
      days = forecasts.fetch(zone.id)
      next if days.empty?

      {id: zone.id, name: zone.name, coordinates: zone.coordinates, location: zone.location,
       systems: zone.pivots.map(&:name), pivot_ids: zone.pivots.map(&:id),
       days: ForecastDaySerializer.new(days).to_h}
    end
  end

  # Until the operation has any planting, what's set up so far, for the checklist (PLAN.md G.6)
  def getting_started(overview)
    fields = overview.pivots.flat_map(&:fields)
    return if fields.any? { |field| field.plantings.any? }

    return if Current.as_of

    {farms: overview.farms.size, systems: overview.pivots.size, fields: fields.size}
  end
end

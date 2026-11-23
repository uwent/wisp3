# Every field's water status today (PLAN.md §11), by farm and pivot: one card per field with this
# season's planting.
class DashboardController < AuthenticatedController
  allow_example :show

  def show
    overview = OperationOverview.new(Current.group)
    irrigation = recent_irrigation(overview)
    render inertia: "Dashboard/Show", props: {
      today: overview.today, getting_started: getting_started(overview), rain: rain(overview),
      farms: overview.props { |pivot| log_props(pivot, irrigation) },
      log_dates: {default: DailyEntryPage.default_date, from: overview.today - LOG_BACK, to: overview.today + LOG_AHEAD}
    }
  end

  private

  # The days the log irrigation dialog offers (older catching up is daily entry's week), and plans ahead
  LOG_BACK = 13
  LOG_AHEAD = 7

  # What the log irrigation dialog needs of a system (docs/plans/phase-9.md §9): the calculator's
  # kind, pump capacity and depth at 100%; its fields now by name, each with its acres and its seasons
  # in Field#planting_on's order, each saying whether it ran here (FieldSeasons: on a day a season ran
  # elsewhere the field isn't this system's, as PivotIrrigationsController#create has it); and
  # their irrigation on the days it offers, {date => {field_id => inches}}, to warn before replacing it
  def log_props(pivot, irrigation)
    fields = pivot.fields.sort_by { |field| [field.name.downcase, field.id] }.map do |field|
      seasons = field.plantings.sort_by(&:order_key)
      {id: field.id, name: field.name, acres: field.area_acres, here: true,
       seasons: seasons.map { |planting| {from: planting.season_start, to: planting.end_date, here: planting.pivot_id == pivot.id} }}
    end
    recent = pivot.fields.each_with_object({}) do |field, days|
      irrigation.fetch(field.id, []).each { |date, inches| (days[date.iso8601] ||= {})[field.id] = inches }
    end
    {kind: pivot.kind, pump_capacity_gpm: pivot.pump_capacity_gpm, inches_at_100: pivot.inches_at_100,
     log_fields: fields, recent_irrigation: recent}
  end

  # The irrigation entered on every field over the days the dialog offers, in one query:
  # {field_id => [[date, inches]]}
  def recent_irrigation(overview)
    today = overview.today
    FieldEntry.where(field_id: overview.pivots.flat_map(&:fields).map(&:id), date: (today - LOG_BACK)..(today + LOG_AHEAD))
      .where.not(irrigation_in: nil).pluck(:field_id, :date, :irrigation_in)
      .group_by(&:first).transform_values { |rows| rows.map { |_, date, inches| [date, inches] } }
  end

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

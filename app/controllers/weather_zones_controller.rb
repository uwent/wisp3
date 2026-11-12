# The operation's weather by zone (G.12; WeatherZone): /weather lists the zones with the week ahead,
# /weather/:id has a zone's season of weather panels (?year=), and export its CSV. Cells are reached
# only through the group's pivots and plantings.
class WeatherZonesController < AuthenticatedController
  def index
    zones = WeatherZone.for_group(Current.group)
    # One zone is the whole page
    return redirect_to weather_zone_path(zones.first.id) if zones.one?

    cell_ids = zones.map(&:id)
    WeatherCell.keep_current(cell_ids)
    forecasts = ForecastDays.by_cell(cell_ids)
    render inertia: "WeatherZones/Index", props: {
      zones: zones.map do |zone|
        WeatherZoneSerializer.new(zone).to_h.merge(forecast: ForecastDaySerializer.new(forecasts.fetch(zone.id)).to_h)
      end,
      updating_pivot_ids: updating_pivot_ids(zones)
    }
  end

  def show
    zone = WeatherZone.find(Current.group, params[:id])
    year = params.fetch(:year, Date.current.year).to_i
    plantings = zone_plantings(zone)
    season = plantings.select { |planting| planting.season_year == year }
    dates = year_dates(year)
    current = year == Date.current.year
    WeatherCell.keep_current([zone.id]) if current
    zones = WeatherZone.for_group(Current.group)
    zones = (zones + [zone]).sort_by(&:sort_key) unless zones.any? { |other| other.id == zone.id }

    render inertia: "WeatherZones/Show", props: {
      zone: WeatherZoneSerializer.new(zone).to_h,
      zones: zones.map { |other| {id: other.id, name: other.name} },
      year:,
      years: (plantings.map(&:season_year) + [Date.current.year]).uniq.sort.reverse,
      weather_from: dates.first,
      weather: WeatherPanelDaySerializer.new(WeatherPanel.new(zone.cell, dates, emergence_date: dates.first).days).to_h,
      # The year's plantings in the zone, which growing degree days can also count from (by planting date)
      plantings: season.sort_by { |planting| [planting.season_start, planting.id] }.map do |planting|
        {id: planting.id, label: "#{planting.plant.name} on #{planting.field.name}", planted: planting.season_start}
      end,
      forecast: current ? ForecastDaySerializer.new(ForecastDays.for(zone.cell)).to_h : [],
      updating_pivot_ids: current ? updating_pivot_ids([zone]) : []
    }
  end

  def export
    zone = WeatherZone.find(Current.group, params[:id])
    year = params.fetch(:year, Date.current.year).to_i
    dates = year_dates(year)
    days = WeatherPanel.new(zone.cell, dates, emergence_date: dates.first).days
    send_data WeatherCsv.new(zone, Current.group, year, days, exported_by: current_user, about_url:).to_csv,
      filename: "wisp-weather-#{zone.name.parameterize}-#{year}.csv", type: "text/csv; charset=utf-8"
  end

  private

  # The group's plantings whose seasons ran on the zone's cell (G.9)
  def zone_plantings(zone)
    Current.group.plantings.includes(:plant, :field).where(weather_cell_id: zone.id).to_a
  end

  # Every zone shows the whole year: January 1 through the forecast this year, or through
  # December 31
  def year_dates(year)
    from = Date.new(year, 1, 1)
    (year == Date.current.year) ? from..(Date.current + Weather::Fetcher::FORECAST_DAYS) : from..Date.new(year, 12, 31)
  end

  # The zones' pivots whose cell has a weather update showing (lib/poll.ts reloads when they land)
  def updating_pivot_ids(zones)
    updating = WeatherCell.updating_ids(zones.map(&:id)).to_set
    zones.select { |zone| updating.include?(zone.id) }.flat_map { |zone| zone.pivots.map(&:id) }
  end
end

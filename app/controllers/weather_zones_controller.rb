# The operation's weather by zone (WeatherZone): /weather lists the zones with the week ahead,
# /weather/44.12,-89.54 has a zone's season of weather panels (?year=), and export its CSV. A zone's
# address is its cell's center; any point in one of the group's cells finds it, and a point
# outside them goes back to the list. Cells are reached only through the group's pivots and plantings.
class WeatherZonesController < AuthenticatedController
  before_action :find_zone, only: [:show, :export]
  allow_example :index, :show, :export, :legacy

  def index
    zones = WeatherZone.for_group(Current.group)
    cell_ids = zones.map(&:id)
    forecasts = ForecastDays.by_cell(cell_ids)
    render inertia: "WeatherZones/Index", props: {
      zones: zones.map do |zone|
        WeatherZoneSerializer.new(zone).to_h.merge(forecast: ForecastDaySerializer.new(forecasts.fetch(zone.id)).to_h)
      end,
      updating_pivot_ids: updating_pivot_ids(zones)
    }
  end

  def show
    zone = @zone
    year = requested_year
    plantings = zone_plantings(zone)
    season = plantings.select { |planting| planting.season_year == year }
    dates = year_dates(year)
    current = year == Current.today.year
    zones = WeatherZone.for_group(Current.group)
    zones = (zones + [zone]).sort_by(&:sort_key) unless zones.any? { |other| other.id == zone.id }

    render inertia: "WeatherZones/Show", props: {
      zone: WeatherZoneSerializer.new(zone).to_h,
      zones: zones.map { |other| {id: other.id, name: other.name, coordinates: other.coordinates, location: other.location} },
      year:,
      years: (plantings.map(&:season_year) + [Current.today.year]).uniq.sort.reverse,
      weather_from: dates.first,
      weather: WeatherPanelDaySerializer.new(WeatherPanel.new(zone.cell, dates, emergence_date: dates.first).days).to_h,
      # The year's plantings in the zone, which growing degree days can also count from (by planting date)
      plantings: season.sort_by { |planting| [planting.season_start, planting.id] }.map do |planting|
        {id: planting.id, label: "#{planting.field.name} #{planting.plant.name}", planted: planting.season_start}
      end,
      forecast: current ? ForecastDaySerializer.new(ForecastDays.for(zone.cell)).to_h : [],
      updating_pivot_ids: current ? updating_pivot_ids([zone]) : []
    }
  end

  def export
    zone = @zone
    year = requested_year
    dates = year_dates(year)
    days = WeatherPanel.new(zone.cell, dates, emergence_date: dates.first).days
    send_csv WeatherCsv.new(zone, Current.group, year, days, exported_by: current_user, about_url:).to_csv,
      "wisp-weather-#{zone.cell.file_location}-#{year}.csv"
  end

  # The old addresses by cell id (/weather/1, /weather/1/export) move to the zone's location
  def legacy
    zone = WeatherZone.find(Current.group, params[:id])
    redirect_to zone_address(zone, export: params[:export]), status: :moved_permanently
  end

  private

  # The zone the address falls in, sent to its exact address if it isn't that; a point outside the
  # group's zones goes back to the list (the same whether another operation has weather there or not)
  def find_zone
    @zone = WeatherZone.at(Current.group, params[:location])
    unless @zone
      return redirect_to weather_zones_path,
        alert: "This operation has no weather zone at #{params[:location].sub(",", ", ")}."
    end
    redirect_to zone_address(@zone, export: action_name == "export") unless params[:location] == @zone.location
  end

  # The zone's page or export at its location, keeping the query (?year=)
  def zone_address(zone, export:)
    query = request.query_parameters
    export ? export_weather_zone_path(zone, query) : weather_zone_path(zone, query)
  end

  # The group's plantings whose seasons ran on the zone's cell
  def zone_plantings(zone)
    Current.group.plantings.includes(:plant, :field).where(weather_cell_id: zone.id).to_a
  end

  # Every zone shows the whole year: January 1 through the forecast this year, or through
  # December 31
  def year_dates(year)
    from = Date.new(year, 1, 1)
    today = Current.today
    (year == today.year) ? from..(today + Weather::Fetcher::FORECAST_DAYS) : from..Date.new(year, 12, 31)
  end

  # Keeps the zones' cells current (WeatherCell.keep_current), and returns their pivots whose cell
  # has a weather update showing (lib/poll.ts reloads when they land)
  def updating_pivot_ids(zones)
    updating = WeatherCell.keep_current_updating_ids(zones.map(&:id)).to_set
    zones.select { |zone| updating.include?(zone.id) }.flat_map { |zone| zone.pivots.map(&:id) }
  end
end

# A weather zone: one weather grid cell (Weather::Grid) and the operation's irrigation systems in it,
# named from them ("North 160 and River"). Pages reach a cell only through the group's systems
# and plantings: a planting keeps the cell its season ran on, so a moved system's old zone
# stays reachable from its ended seasons.
class WeatherZone
  # Names past this many systems end "and 3 more"
  NAMED = 3

  attr_reader :cell, :systems

  # The zones of the group's irrigation systems as they are now, by name
  def self.for_group(group)
    systems = group.systems.includes(:farm, :weather_cell, :fields).where.not(weather_cell_id: nil).to_a
    systems.group_by(&:weather_cell).map { |cell, cell_systems| new(cell, cell_systems) }.sort_by(&:sort_key)
  end

  # The zone of one of the group's cells (its systems', or a planting's from an earlier season), or
  # ActiveRecord::RecordNotFound
  def self.find(group, cell_id)
    cell = WeatherCell.where(id: cell_ids(group)).find(cell_id)
    systems = group.systems.includes(:farm, :fields).where(weather_cell_id: cell.id)
      .or(group.systems.includes(:farm, :fields).where(id: group.plantings.where(weather_cell_id: cell.id).select(:system_id)))
    new(cell, systems.to_a.uniq)
  end

  # The zone of the group's cell a point ("44.1234,-89.5") falls in, or nil: a point outside the
  # group's cells, or not a place. Never creates a cell.
  def self.at(group, location)
    latitude, longitude = location.to_s.split(",").map { |part| Float(part, exception: false) }
    return unless latitude && longitude && latitude.abs <= 90 && longitude.abs <= 180

    point = Weather::Grid.cell_for(latitude, longitude)
    cell = WeatherCell.where(id: cell_ids(group))
      .find_by(latitude: point.latitude.round(6), longitude: point.longitude.round(6))
    cell && find(group, cell.id)
  end

  # Every cell the group's pages may show
  def self.cell_ids(group)
    group.systems.where.not(weather_cell_id: nil).pluck(:weather_cell_id) |
      group.plantings.where.not(weather_cell_id: nil).pluck(:weather_cell_id)
  end

  # A page's link to a cell's zone and, unless forecast: false, its week ahead (ForecastStrip):
  # {weather_zone: {id, name, location} or nil, forecast: [ForecastDay]}
  def self.page_props(group, cell, forecast: true)
    return {weather_zone: nil, forecast: []} unless cell

    systems = group.systems.where(weather_cell_id: cell.id).order(:name)
    {
      weather_zone: {id: cell.id, name: new(cell, systems.to_a).name, location: cell.location},
      forecast: forecast ? ForecastDaySerializer.new(ForecastDays.for(cell)).to_h : []
    }
  end

  def initialize(cell, systems)
    @cell, @systems = cell, systems.sort_by { |system| [system.name.downcase, system.id] }
  end

  def id = cell.id

  # Its address: weather_zone_path(zone) is /weather/44.12,-89.54
  def location = cell.location

  def to_param = location

  # The fields on its systems, by name
  def fields = systems.flat_map(&:fields).sort_by { |field| [field.name.downcase, field.id] }

  # "North 160", "North 160 and River", "North 160, River and South", "A, B, C and 2 more"
  def name
    names = systems.map(&:name).uniq
    return "Weather zone at #{coordinates}" if names.empty?
    return names.to_sentence(two_words_connector: " and ", last_word_connector: " and ") if names.size <= NAMED

    "#{names.first(NAMED).join(", ")} and #{names.size - NAMED} more"
  end

  # "44.12°N, 89.54°W"
  def coordinates
    format("%.2f°%s, %.2f°%s", cell.latitude.abs, cell.latitude.negative? ? "S" : "N",
      cell.longitude.abs, cell.longitude.negative? ? "W" : "E")
  end

  def sort_key = [name.downcase, id]
end

# A weather zone: one weather grid cell (Weather::Grid) and the operation's irrigation systems in it,
# named from them ("North 160 and River", G.12). Pages reach a cell only through the group's pivots
# and plantings: a planting keeps the cell its season ran on (G.9), so a moved pivot's old zone
# stays reachable from its ended seasons.
class WeatherZone
  # Names past this many systems end "and 3 more"
  NAMED = 3

  attr_reader :cell, :pivots

  # The zones of the group's irrigation systems as they are now, by name
  def self.for_group(group)
    pivots = group.pivots.includes(:farm, :weather_cell).where.not(weather_cell_id: nil).to_a
    pivots.group_by(&:weather_cell).map { |cell, cell_pivots| new(cell, cell_pivots) }.sort_by(&:sort_key)
  end

  # The zone of one of the group's cells (its pivots', or a planting's from an earlier season), or
  # ActiveRecord::RecordNotFound
  def self.find(group, cell_id)
    cell = WeatherCell.where(id: cell_ids(group)).find(cell_id)
    pivots = group.pivots.includes(:farm).where(weather_cell_id: cell.id)
      .or(group.pivots.includes(:farm).where(id: group.plantings.where(weather_cell_id: cell.id).select("pivots.id")))
    new(cell, pivots.to_a.uniq)
  end

  # Every cell the group's pages may show
  def self.cell_ids(group)
    group.pivots.where.not(weather_cell_id: nil).pluck(:weather_cell_id) |
      group.plantings.where.not(weather_cell_id: nil).pluck(:weather_cell_id)
  end

  # A page's link to a cell's zone and, unless forecast: false, its week ahead (ForecastStrip):
  # {weather_zone: {id, name} or nil, forecast: [ForecastDay]}
  def self.page_props(group, cell, forecast: true)
    return {weather_zone: nil, forecast: []} unless cell

    pivots = group.pivots.where(weather_cell_id: cell.id).order(:name)
    {
      weather_zone: {id: cell.id, name: new(cell, pivots.to_a).name},
      forecast: forecast ? ForecastDaySerializer.new(ForecastDays.for(cell)).to_h : []
    }
  end

  def initialize(cell, pivots)
    @cell, @pivots = cell, pivots.sort_by { |pivot| [pivot.name.downcase, pivot.id] }
  end

  def id = cell.id

  # "North 160", "North 160 and River", "North 160, River and South", "A, B, C and 2 more"
  def name
    names = pivots.map(&:name).uniq
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

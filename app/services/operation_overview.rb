# A group's farms, systems and fields with each field's status today, for the dashboard and the map:
# farms and systems by name, one card per field with a summary for each of its
# plantings in season (several on a field of plots; or the nearest this year).
# Systems without fields are listed too, so the hierarchy matches setup. weather_updating marks a system
# whose cell has a WeatherUpdateJob queued or running; the pages reload until it clears.
class OperationOverview
  attr_reader :today, :year, :farms

  # year: the season shown (the map's); this year by default. Today is the example farm's day
  # there (Current.today), whose weather stays as stored.
  def initialize(group, today: Current.today, year: today.year)
    @today = today
    @year = year
    @farms = group.farms.order(:name).includes(:irrigation_groups, systems: [:weather_cell, :irrigation_group,
      {fields: [:soil_type, {plantings: [:plant, :canopy_observations, :canopy_cuttings, :soil_type]}]}]).to_a
    cell_ids = systems.map(&:weather_cell_id).uniq
    # Read before the balances, so weather landing in between still gets a reload
    @updating = WeatherCell.keep_current_updating_ids(cell_ids).to_set
    @statuses = FieldStatuses.for(systems.flat_map(&:fields), today:, year:)
  end

  def systems = @systems ||= farms.flat_map { |farm| sorted(farm) }

  # The seasons there's something to show for: this year and every year with a planting, latest first
  def years = (systems.flat_map { |system| system.fields.flat_map { |field| field.plantings.map(&:season_year) } } << today.year).uniq.sort.reverse

  # Farms (with their irrigation groups) › systems › field cards; a block adds to each system's hash
  def props
    farms.map do |farm|
      systems = sorted(farm).map do |system|
        {id: system.id, name: system.name, kind_name: system.kind_name, irrigation_group_id: system.irrigation_group_id,
         weather_updating: @updating.include?(system.weather_cell_id),
         **(block_given? ? yield(system) : {}),
         fields: system.fields.map { |field| card(field) }}
      end
      {id: farm.id, name: farm.name,
       irrigation_groups: farm.irrigation_groups.map { |irrigation_group| irrigation_group.slice(:id, :name).symbolize_keys }, systems:}
    end
  end

  private

  def sorted(farm) = farm.systems.sort_by(&:name)

  def card(field)
    {id: field.id, name: field.name, plantings: @statuses[field.id].map { |status| PlantingSummarySerializer.new(status).to_h }}
  end
end

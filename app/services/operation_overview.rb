# A group's farms, pivots and fields with each field's status today, for the dashboard and the map
# (PLAN.md §11, Phase 7): farms and pivots by name, one card per field with a summary for each of its
# plantings in season (several on a field of plots, G.11; or the nearest this year).
# Pivots without fields are listed too, so the hierarchy matches setup. weather_updating marks a pivot
# whose cell has a WeatherUpdateJob queued or running; the pages reload until it clears.
class OperationOverview
  attr_reader :today, :year, :farms

  # year: the season shown (the map's, G.14); this year by default
  def initialize(group, today: Date.current, year: today.year)
    @today = today
    @year = year
    @farms = group.farms.order(:name).includes(:pivot_groups, pivots: [:weather_cell,
      {fields: [:soil_type, {plantings: [:plant, :canopy_observations, :canopy_cuttings, :soil_type]}]}]).to_a
    cell_ids = pivots.map(&:weather_cell_id).uniq
    WeatherCell.keep_current(cell_ids)
    # Read before the balances, so weather landing in between still gets a reload
    @updating = WeatherCell.updating_ids(cell_ids).to_set
    @statuses = FieldStatuses.for(pivots.flat_map(&:fields), today:, year:)
  end

  def pivots = @pivots ||= farms.flat_map { |farm| sorted(farm) }

  # The seasons there's something to show for: this year and every year with a planting, latest first
  def years = (pivots.flat_map { |pivot| pivot.fields.flat_map { |field| field.plantings.map(&:season_year) } } << today.year).uniq.sort.reverse

  # Farms (with their irrigation groups) › pivots › field cards; a block adds to each pivot's hash
  def props
    farms.map do |farm|
      pivots = sorted(farm).map do |pivot|
        {id: pivot.id, name: pivot.name, kind_name: pivot.kind_name, pivot_group_id: pivot.pivot_group_id,
         weather_updating: @updating.include?(pivot.weather_cell_id),
         **(block_given? ? yield(pivot) : {}),
         fields: pivot.fields.map { |field| card(field) }}
      end
      {id: farm.id, name: farm.name,
       pivot_groups: farm.pivot_groups.map { |pivot_group| pivot_group.slice(:id, :name).symbolize_keys }, pivots:}
    end
  end

  private

  def sorted(farm) = farm.pivots.sort_by(&:name)

  def card(field)
    {id: field.id, name: field.name, plantings: @statuses[field.id].map { |status| PlantingSummarySerializer.new(status).to_h }}
  end
end

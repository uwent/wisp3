# A group's farms, pivots and fields with each field's status today, for the dashboard and the map
# (PLAN.md §11, Phase 7): farms and pivots by name, one card per field with this season's planting.
# Pivots without fields are listed too, so the hierarchy matches setup.
class OperationOverview
  attr_reader :today, :farms

  def initialize(group, today: Date.current)
    @today = today
    @farms = group.farms.order(:name).includes(pivots: [:weather_cell,
      {fields: [:soil_type, {plantings: [:plant, :canopy_observations]}]}]).to_a
    WeatherCell.keep_current(pivots.map(&:weather_cell_id).uniq)
    @statuses = FieldStatuses.for(pivots.flat_map(&:fields), today:)
  end

  def pivots = @pivots ||= farms.flat_map { |farm| sorted(farm) }

  # Farms › pivots › field cards; a block adds to each pivot's hash
  def props
    farms.map do |farm|
      {id: farm.id, name: farm.name, pivots: sorted(farm).map do |pivot|
        {id: pivot.id, name: pivot.name, **(block_given? ? yield(pivot) : {}),
         fields: pivot.fields.map { |field| card(field) }}
      end}
    end
  end

  private

  def sorted(farm) = farm.pivots.sort_by(&:name)

  def card(field)
    status = @statuses[field.id]
    {id: field.id, name: field.name, summary: status && PlantingSummarySerializer.new(status).to_h}
  end
end

# Every field's water status today (PLAN.md §11): one card per field with this season's planting
class DashboardController < AuthenticatedController
  def show
    today = Date.current
    fields = Current.group.fields.includes(:soil_type, pivot: [:farm, :weather_cell],
      plantings: [:plant, :canopy_observations])

    cards = fields.sort_by { |field| [field.pivot.farm.name, field.pivot.name, field.name] }.map do |field|
      planting = field.planting_on(today) ||
        field.plantings.select { |p| p.season_year == today.year }.min_by { |p| (p.season_start - today).abs }
      {
        field: {id: field.id, name: field.name},
        pivot: {id: field.pivot.id, name: field.pivot.name},
        farm: {id: field.pivot.farm.id, name: field.pivot.farm.name},
        summary: planting && PlantingSummarySerializer.new(PlantingStatus.new(planting, today:)).to_h
      }
    end

    render inertia: "Dashboard/Show", props: {
      today:,
      cards:,
      farm_count: Current.group.farms.count
    }
  end
end

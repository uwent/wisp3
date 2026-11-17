# A planting's own season length (PLAN.md Phase 8 G.7): days from emergence to harvest, stretching its
# crop's canopy curve in time. NULL follows the crop's typical season.
class AddSeasonDaysToPlantings < ActiveRecord::Migration[8.1]
  def change
    add_column :plantings, :season_days, :integer
    add_check_constraint :plantings, "season_days IS NULL OR season_days BETWEEN 20 AND 250", name: "plantings_season_days_range"
  end
end

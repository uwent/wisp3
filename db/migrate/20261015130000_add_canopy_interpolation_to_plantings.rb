# How a planting's canopy readings combine with its crop's curve (PLAN.md Phase 6.7): "curve"
# follows it between and after readings, "linear" draws straight lines; NULL follows the crop's
# default (the curve where there is one).
class AddCanopyInterpolationToPlantings < ActiveRecord::Migration[8.1]
  def change
    add_column :plantings, :canopy_interpolation, :string
    add_check_constraint :plantings, "canopy_interpolation IN ('linear', 'curve')", name: "plantings_canopy_interpolation"
  end
end

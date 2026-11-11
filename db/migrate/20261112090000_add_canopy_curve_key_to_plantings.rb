# A planting of a crop without its own canopy curve picks a generic one, or none (readings only);
# NULL is the crop's own curve or its generic default (PLAN.md Phase 8 G.3)
class AddCanopyCurveKeyToPlantings < ActiveRecord::Migration[8.1]
  def change
    add_column :plantings, :canopy_curve_key, :string
  end
end

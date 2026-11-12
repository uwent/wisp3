# Plots no longer have a place in their field (G.14): the map shows a field's plantings as badges
# at its center. Rolling back brings the columns back empty.
class RemovePinsFromPlantings < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :plantings, "(latitude IS NULL) = (longitude IS NULL)", name: "plantings_pin_both"
    remove_column :plantings, :latitude, :float
    remove_column :plantings, :longitude, :float
  end
end

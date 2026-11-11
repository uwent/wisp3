# PLAN.md Phase 8 G.11: a plot can grow on its own soil, rather than following its field's (a
# research field's plots may sit on different soils). Whole-field plantings always follow the field.
class AddOwnSoilToPlantings < ActiveRecord::Migration[8.1]
  def change
    add_column :plantings, :own_soil, :boolean, null: false, default: false
    add_check_constraint :plantings, "partial OR NOT own_soil", name: "plantings_own_soil_partial"
  end
end

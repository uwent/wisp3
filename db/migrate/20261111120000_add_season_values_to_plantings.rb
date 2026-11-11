# PLAN.md Phase 8 G.9: a planting keeps the field's soil and area and its pivot's weather cell, so
# editing a field or moving a pivot for a new season leaves earlier seasons as they ran. Filled
# from each planting's field and pivot as they are now.
class AddSeasonValuesToPlantings < ActiveRecord::Migration[8.1]
  def up
    add_reference :plantings, :soil_type, foreign_key: true
    add_column :plantings, :field_capacity, :float
    add_column :plantings, :perm_wilting_pt, :float
    add_column :plantings, :area_acres, :float
    add_reference :plantings, :weather_cell, foreign_key: {on_delete: :nullify}

    execute <<~SQL
      UPDATE plantings
      SET soil_type_id = fields.soil_type_id,
          field_capacity = fields.field_capacity,
          perm_wilting_pt = fields.perm_wilting_pt,
          area_acres = fields.area_acres,
          weather_cell_id = pivots.weather_cell_id
      FROM fields JOIN pivots ON pivots.id = fields.pivot_id
      WHERE fields.id = plantings.field_id
    SQL

    change_column_null :plantings, :soil_type_id, false
    add_check_constraint :plantings, "area_acres IS NULL OR area_acres > 0", name: "plantings_area_positive"
  end

  def down
    remove_check_constraint :plantings, name: "plantings_area_positive"
    remove_reference :plantings, :weather_cell, foreign_key: true
    remove_column :plantings, :area_acres
    remove_column :plantings, :perm_wilting_pt
    remove_column :plantings, :field_capacity
    remove_reference :plantings, :soil_type, foreign_key: true
  end
end

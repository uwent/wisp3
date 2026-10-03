class CreateReferenceData < ActiveRecord::Migration[8.1]
  def change
    create_table :plants do |t|
      t.string :key, null: false, index: {unique: true}
      t.string :name, null: false
      t.float :default_max_root_zone_depth, null: false
      t.string :canopy_model
      t.timestamps
    end

    create_table :soil_types do |t|
      t.string :key, null: false, index: {unique: true}
      t.string :name, null: false
      t.float :field_capacity, null: false
      t.float :perm_wilting_pt, null: false
      t.timestamps
      t.check_constraint "perm_wilting_pt > 0 AND perm_wilting_pt < field_capacity AND field_capacity < 0.6", name: "soil_types_water_fractions"
    end
  end
end

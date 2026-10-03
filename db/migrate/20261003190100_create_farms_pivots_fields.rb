class CreateFarmsPivotsFields < ActiveRecord::Migration[8.1]
  def change
    # Replaces the legacy precip_use_agwx flag, which was inverted (PLAN.md C1)
    add_column :groups, :use_model_precip, :boolean, null: false, default: true

    create_table :farms do |t|
      t.references :group, null: false, foreign_key: true
      t.string :name, null: false
      t.text :notes
      t.timestamps
    end

    create_table :pivots do |t|
      t.references :farm, null: false, foreign_key: true
      t.string :name, null: false
      # Required with no default: half the legacy pivots sat at a placeholder location (A5)
      t.float :latitude, null: false
      t.float :longitude, null: false
      t.float :radius_ft
      t.float :arc_start_deg # NULL arc = full circle
      t.float :arc_end_deg
      t.string :equipment
      t.float :pump_capacity_gpm
      t.text :notes
      t.timestamps
      t.check_constraint "radius_ft IS NULL OR radius_ft > 0", name: "pivots_radius_positive"
      t.check_constraint "pump_capacity_gpm IS NULL OR pump_capacity_gpm > 0", name: "pivots_pump_capacity_positive"
      t.check_constraint "(arc_start_deg IS NULL) = (arc_end_deg IS NULL)", name: "pivots_arc_both_or_neither"
    end

    create_table :fields do |t|
      t.references :pivot, null: false, foreign_key: true
      t.references :soil_type, null: false, foreign_key: true
      t.string :name, null: false
      t.float :area_acres
      # NULL = use the soil type's value (legacy used 0.0 for that, C14)
      t.float :field_capacity
      t.float :perm_wilting_pt
      t.jsonb :boundary # GeoJSON, for areas that aren't the whole pivot circle
      t.text :notes
      t.timestamps
      t.check_constraint "area_acres IS NULL OR area_acres > 0", name: "fields_area_positive"
    end
  end
end

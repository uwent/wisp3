class CreateDailyEntries < ActiveRecord::Migration[8.1]
  # What a grower records for a day. NULL = not entered; 0.0 = entered as zero (C5).
  def entry_columns(t)
    t.date :date, null: false
    t.float :rain_in
    t.float :irrigation_in
    t.float :soil_moisture_pct
    t.text :notes
    t.timestamps
    t.check_constraint "rain_in IS NULL OR rain_in >= 0", name: "#{t.name}_rain_nonnegative"
    t.check_constraint "irrigation_in IS NULL OR irrigation_in >= 0", name: "#{t.name}_irrigation_nonnegative"
    t.check_constraint "soil_moisture_pct IS NULL OR soil_moisture_pct BETWEEN 0 AND 100", name: "#{t.name}_moisture_range"
  end

  def change
    create_table :field_entries do |t|
      t.references :field, null: false, foreign_key: true, index: false
      entry_columns(t)
      t.index [:field_id, :date], unique: true
    end

    # Field groups: shared entries for several fields, applied when read (not copied, C12)
    create_table :field_groups do |t|
      t.references :group, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end

    create_table :field_group_members do |t|
      t.references :field_group, null: false, foreign_key: true, index: false
      t.references :field, null: false, foreign_key: true
      t.timestamps
      t.index [:field_group_id, :field_id], unique: true
    end

    create_table :field_group_entries do |t|
      t.references :field_group, null: false, foreign_key: true, index: false
      entry_columns(t)
      t.index [:field_group_id, :date], unique: true
    end

    # Irrigation entered once for a pivot, applied to its fields when read (D9)
    create_table :pivot_irrigations do |t|
      t.references :pivot, null: false, foreign_key: true, index: false
      t.date :date, null: false
      t.float :inches
      t.float :run_hours # converted to inches from pump capacity and irrigated area
      t.bigint :field_ids, array: true # NULL = every field under the pivot
      t.text :notes
      t.timestamps
      t.index [:pivot_id, :date], unique: true
      t.check_constraint "num_nonnulls(inches, run_hours) >= 1", name: "pivot_irrigations_amount"
      t.check_constraint "inches IS NULL OR inches >= 0", name: "pivot_irrigations_inches_nonnegative"
      t.check_constraint "run_hours IS NULL OR run_hours >= 0", name: "pivot_irrigations_run_hours_nonnegative"
    end
  end
end

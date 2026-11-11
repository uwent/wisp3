# PLAN.md Phase 8 G.11: a field is the land, a planting what grows on it. A planting covers the
# whole field (as before) or part of it (partial: a plot of length × width, or acres, with an
# optional pin). Part-field plantings may overlap each other in time; a whole-field one overlaps
# nothing. A part-field planting can have its own irrigation, soil moisture readings and notes
# (planting_entries), which come before the field's for its balance (DailyInputs).
class AddPartFieldPlantings < ActiveRecord::Migration[8.1]
  def change
    change_table :plantings, bulk: true do |t|
      t.boolean :partial, null: false, default: false
      t.float :plot_length_ft
      t.float :plot_width_ft
      t.float :latitude
      t.float :longitude
    end
    add_check_constraint :plantings, "NOT partial OR area_acres IS NOT NULL", name: "plantings_partial_area"
    add_check_constraint :plantings, "(plot_length_ft IS NULL) = (plot_width_ft IS NULL)", name: "plantings_plot_both"
    add_check_constraint :plantings, "plot_length_ft IS NULL OR (partial AND plot_length_ft > 0 AND plot_width_ft > 0)",
      name: "plantings_plot_partial"
    add_check_constraint :plantings, "(latitude IS NULL) = (longitude IS NULL)", name: "plantings_pin_both"

    # A whole-field planting takes an unbounded range, which overlaps every other planting's; a
    # part-field one takes a range of its own id, which overlaps only a whole-field one's
    remove_exclusion_constraint :plantings, "field_id WITH =, daterange(season_start, end_date, '[]') WITH &&",
      using: :gist, name: "plantings_no_overlap"
    add_exclusion_constraint :plantings,
      "field_id WITH =, daterange(season_start, end_date, '[]') WITH &&, " \
      "(CASE WHEN partial THEN int8range(id, id + 1) ELSE int8range(NULL, NULL) END) WITH &&",
      using: :gist, name: "plantings_no_overlap"

    create_table :planting_entries do |t|
      t.references :planting, null: false, foreign_key: true, index: false
      t.date :date, null: false
      t.float :irrigation_in
      t.float :soil_moisture_pct
      t.text :notes
      t.timestamps
      t.index [:planting_id, :date], unique: true
      t.check_constraint "irrigation_in IS NULL OR irrigation_in >= 0", name: "planting_entries_irrigation_nonnegative"
      t.check_constraint "soil_moisture_pct IS NULL OR soil_moisture_pct BETWEEN 0 AND 100",
        name: "planting_entries_moisture_range"
    end
  end
end

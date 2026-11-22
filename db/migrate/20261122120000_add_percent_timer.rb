# A center pivot's or linear's percent timer (docs/plans/phase-9.md §8): the depth a circle (or pass)
# puts on at 100%, on the system; irrigation entered as the timer's percent and the circles run,
# converted when read (PivotIrrigation#applied_inches); a field's own irrigation entered as a percent
# keeps it beside the inches it came to.
class AddPercentTimer < ActiveRecord::Migration[8.1]
  def change
    add_column :pivots, :inches_at_100, :float
    add_check_constraint :pivots, "inches_at_100 IS NULL OR inches_at_100 > 0", name: "pivots_inches_at_100_positive"
    add_check_constraint :pivots, "inches_at_100 IS NULL OR kind IN ('center', 'linear')", name: "pivots_inches_at_100_kind"

    add_column :pivot_irrigations, :percent_timer, :float
    add_column :pivot_irrigations, :circles, :float
    add_check_constraint :pivot_irrigations, "percent_timer IS NULL OR (percent_timer > 0 AND percent_timer <= 100)",
      name: "pivot_irrigations_percent_timer_range"
    add_check_constraint :pivot_irrigations, "circles IS NULL OR circles > 0", name: "pivot_irrigations_circles_positive"
    remove_check_constraint :pivot_irrigations, "num_nonnulls(inches, run_hours) >= 1", name: "pivot_irrigations_amount"
    add_check_constraint :pivot_irrigations, "num_nonnulls(inches, run_hours, percent_timer) >= 1", name: "pivot_irrigations_amount"

    add_column :field_entries, :irrigation_pct, :float
    add_check_constraint :field_entries, "irrigation_pct IS NULL OR (irrigation_pct > 0 AND irrigation_pct <= 100 AND irrigation_in IS NOT NULL)",
      name: "field_entries_irrigation_pct"
  end
end

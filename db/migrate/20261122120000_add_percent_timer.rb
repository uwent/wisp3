# A center pivot's or linear's percent timer: the depth a circle (or pass)
# puts on at 100%, on the system, for the irrigation calculator's percent (depth at 100% × 100 ÷
# percent × circles). Irrigation itself is stored in inches only (D15).
class AddPercentTimer < ActiveRecord::Migration[8.1]
  def change
    add_column :pivots, :inches_at_100, :float
    add_check_constraint :pivots, "inches_at_100 IS NULL OR inches_at_100 > 0", name: "pivots_inches_at_100_positive"
    add_check_constraint :pivots, "inches_at_100 IS NULL OR kind IN ('center', 'linear')", name: "pivots_inches_at_100_kind"
  end
end

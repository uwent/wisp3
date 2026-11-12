# Irrigation systems other than pivots (PLAN.md Phase 8 G.5): travelers, solid set, drip and a
# location only, each a point with no dimensions (its area comes from its fields).
class AddPointKindsToPivots < ActiveRecord::Migration[8.1]
  LINEAR = "radius_ft IS NULL AND arc_start_deg IS NULL AND length_ft IS NOT NULL AND travel_ft IS NOT NULL " \
    "AND travel_bearing_deg IS NOT NULL AND length_ft > 0 AND length_ft <= 3300 AND travel_ft > 0 " \
    "AND travel_ft <= 5280 AND travel_bearing_deg >= 0 AND travel_bearing_deg <= 179"

  def change
    remove_check_constraint :pivots, "kind IN ('center', 'linear')", name: "pivots_kind"
    add_check_constraint :pivots, "kind IN ('center', 'linear', 'traveler', 'solid_set', 'drip', 'point')",
      name: "pivots_kind"
    # Was "kind = 'center' OR …", which held every other kind to a linear's shape
    remove_check_constraint :pivots, "kind = 'center' OR (#{LINEAR})", name: "pivots_linear_shape"
    add_check_constraint :pivots, "kind <> 'linear' OR (#{LINEAR})", name: "pivots_linear_shape"
    add_check_constraint :pivots, "kind IN ('center', 'linear') OR (radius_ft IS NULL AND arc_start_deg IS NULL)",
      name: "pivots_point_shape"
  end
end

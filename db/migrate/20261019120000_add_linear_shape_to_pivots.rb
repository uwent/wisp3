# A pivot is a center pivot (a circle, or an arc for a partial circle) or a linear move: a machine
# length_ft long traveling travel_ft along travel_bearing_deg (whole degrees from north, 0–179, as
# it runs both ways), a rectangle centered on its latitude and longitude. Each has a realistic
# maximum size (Pivot::MAX_RADIUS_FT, MAX_LINEAR_LENGTH_FT, MAX_LINEAR_TRAVEL_FT).
class AddLinearShapeToPivots < ActiveRecord::Migration[8.1]
  def change
    add_column :pivots, :kind, :string, null: false, default: "center"
    add_column :pivots, :length_ft, :float
    add_column :pivots, :travel_ft, :float
    add_column :pivots, :travel_bearing_deg, :integer

    add_check_constraint :pivots, "kind IN ('center', 'linear')", name: "pivots_kind"
    add_check_constraint :pivots, "radius_ft IS NULL OR radius_ft <= 3000", name: "pivots_radius_max"
    add_check_constraint :pivots,
      "kind = 'linear' OR (length_ft IS NULL AND travel_ft IS NULL AND travel_bearing_deg IS NULL)",
      name: "pivots_center_shape"
    add_check_constraint :pivots,
      "kind = 'center' OR (radius_ft IS NULL AND arc_start_deg IS NULL " \
      "AND length_ft IS NOT NULL AND travel_ft IS NOT NULL AND travel_bearing_deg IS NOT NULL " \
      "AND length_ft > 0 AND length_ft <= 3300 AND travel_ft > 0 AND travel_ft <= 5280 " \
      "AND travel_bearing_deg BETWEEN 0 AND 179)",
      name: "pivots_linear_shape"
  end
end

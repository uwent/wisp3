# A field's outline (PLAN.md Phase 8 G.10) is a GeoJSON geometry object or NULL; FieldBoundary
# checks the rest (the column has been there, unused, since the first migration)
class CheckFieldsBoundaryIsObject < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :fields, "boundary IS NULL OR jsonb_typeof(boundary) = 'object'", name: "fields_boundary_object"
  end
end

# A field's outline is one polygon with one ring (PLAN.md Phase 8 G.14): an outline stored as a
# MultiPolygon, or with holes, keeps its largest part's outer ring. Only demo, test and staging data
# had outlines by then. Not reversible: the dropped parts and holes are gone.
class ReduceFieldBoundariesToOneRing < ActiveRecord::Migration[8.1]
  class Field < ActiveRecord::Base
    self.table_name = "fields"
  end

  def up
    Field.where.not(boundary: nil).find_each do |field|
      geometry = field.boundary
      polygons = case geometry["type"]
      when "Polygon" then [geometry["coordinates"]]
      when "MultiPolygon" then geometry["coordinates"]
      else next
      end
      next if geometry["type"] == "Polygon" && polygons.first.length == 1
      outer = polygons.map(&:first).compact.max_by { |ring| planar_area(ring) }
      field.update_columns(boundary: outer && {"type" => "Polygon", "coordinates" => [outer]})
    end
  end

  def down
  end

  private

  # In square degrees: enough to compare one field's parts
  def planar_area(ring)
    ring.each_cons(2).sum { |(x0, y0), (x1, y1)| x0 * y1 - x1 * y0 }.abs / 2
  end
end

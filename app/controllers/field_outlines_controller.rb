# A field's outline page (PLAN.md Phase 8 G.10): the outline drawn on the map, copied from its
# irrigation system's shape or read from a file in the browser, with its acres offered for the
# field's area and the soil survey's dominant soil offered for its soil.
# The outline is for the map and suggestions only; the balance never reads it.
class FieldOutlinesController < AuthenticatedController
  def show
    field = Current.group.fields.includes(:soil_type, pivot: :farm, plantings: :plant).find(params[:field_id])
    others = Current.group.fields.includes(:pivot).where.not(id: field.id).where.not(boundary: nil)
    render inertia: "Fields/Outline", props: {
      field: FieldSerializer.new(field).to_h,
      pivot: field.pivot.slice(:id, :name, :kind_name, *PivotSerializer::SHAPE),
      # Nearby systems and other fields' outlines, drawn for reference
      other_pivots: Current.group.pivots.where.not(id: field.pivot_id).map { |pivot| pivot.slice(:id, :name, *PivotSerializer::SHAPE) },
      other_fields: others.map { |other| {id: other.id, name: other.name, boundary: other.boundary} },
      soil_types: SoilTypeSerializer.new(SoilType.order(:field_capacity, :perm_wilting_pt)).to_h,
      from: (params[:from] == "setup") ? "setup" : "field"
    }
  end

  # outline: boundary (GeoJSON as JSON, blank to remove), and optionally area_acres and soil_type_id
  # from the page's offers
  def update
    field = Current.group.fields.find(params[:field_id])
    values = outline_params
    field.assign_attributes(values.slice(:area_acres, :soil_type_id).compact_blank)
    field.boundary = values[:boundary] if values.key?(:boundary)
    return redirect_with_errors(field_outline_path(field, from: params[:from]), field.errors.to_hash) unless field.save

    destination = (params[:from] == "setup") ? setup_path : field_path(field)
    redirect_to destination, notice: "Saved the outline of #{field.name}"
  end

  private

  def outline_params
    params.expect(outline: [:boundary, :area_acres, :soil_type_id])
  end
end

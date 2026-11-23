# Field outlines for many fields at once: a file of shapes is read in the
# browser (a zipped shapefile, GeoJSON or KML), and each shape is matched to one of the operation's
# fields or makes a new field under an irrigation system (OutlineImport). Only the outlines and the
# new fields' values are sent.
class OutlineImportsController < AuthenticatedController
  def new
    pivots = Current.group.pivots.includes(:farm).sort_by { |pivot| [pivot.farm.name, pivot.name] }
    render inertia: "Setup/ImportOutlines", props: {
      pivots: pivots.map { |pivot| pivot.slice(:id, :name, :kind_name, *PivotSerializer::SHAPE).merge(farm: pivot.farm.name) },
      fields: Current.group.fields.order(:name).map do |field|
        field.slice(:id, :name, :pivot_id, :area_acres).merge(outlined: !field.boundary.nil?)
      end,
      soil_types: ReferenceProps.soil_types,
      default_soil_type_id: ReferenceProps.default_soil_type_id
    }
  end

  # outline_import: rows, each a boundary (GeoJSON as JSON) and either field_id (an existing field)
  # or pivot_id, name, soil_type_id and area_acres (a new field); use_area sets existing fields' area
  # from their outlines too (OutlineImport). Errors come back keyed by row ("rows.2.name").
  def create
    values = import_params
    rows = indexed_list(values[:rows])
    return redirect_with_errors(new_outline_import_path, {rows: "Choose at least one shape to save"}) if rows.empty?

    import = OutlineImport.new(Current.group, rows, use_area: values[:use_area] == "1")
    return redirect_with_errors(new_outline_import_path, import.errors) unless import.save

    redirect_to setup_path, notice: import.notice
  end

  private

  def import_params
    params.expect(outline_import: [:use_area, rows: [[:boundary, :field_id, :pivot_id, :name, :soil_type_id, :area_acres]]])
  end
end

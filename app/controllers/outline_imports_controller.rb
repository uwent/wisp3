# Field outlines for many fields at once (PLAN.md Phase 8 G.10): a file of shapes is read in the
# browser (a zipped shapefile, GeoJSON or KML), and each shape is matched to one of the operation's
# fields or makes a new field under an irrigation system. Only the outlines and the new fields'
# values are sent. One save, in a transaction: every row saves, or none does.
class OutlineImportsController < AuthenticatedController
  def new
    pivots = Current.group.pivots.includes(:farm).sort_by { |pivot| [pivot.farm.name, pivot.name] }
    render inertia: "Setup/ImportOutlines", props: {
      pivots: pivots.map { |pivot| pivot.slice(:id, :name, :kind_name, *PivotSerializer::SHAPE).merge(farm: pivot.farm.name) },
      fields: Current.group.fields.order(:name).map do |field|
        field.slice(:id, :name, :pivot_id, :area_acres).merge(outlined: !field.boundary.nil?)
      end,
      soil_types: SoilTypeSerializer.new(SoilType.order(:field_capacity, :perm_wilting_pt)).to_h,
      default_soil_type_id: SoilType.find_by(key: SoilType::DEFAULT_KEY)&.id
    }
  end

  # outline_import: rows, each a boundary (GeoJSON as JSON) and either field_id (an existing field)
  # or pivot_id, name, soil_type_id and area_acres (a new field); use_area sets existing fields' area
  # from their outlines too. Errors come back keyed by row ("rows.2.name").
  def create
    values = import_params
    rows = indexed_list(values[:rows])
    return redirect_with_errors(new_outline_import_path, {rows: "Choose at least one shape to save"}) if rows.empty?

    errors = {}
    added = 0
    Field.transaction do
      seen = {}
      rows.each_with_index do |row, index|
        field = field_for(row)
        if row[:field_id].present? && seen.key?(field.id)
          errors["rows.#{index}.field_id"] = ["is also in row #{seen[field.id] + 1}"]
          next
        end
        seen[field.id] = index if field.persisted?
        added += 1 if field.new_record?
        field.boundary = row[:boundary]
        field.area_acres = field.boundary_acres&.round(2) if values[:use_area] == "1" && field.persisted? && field.boundary
        next if field.save
        field.errors.to_hash.each { |attribute, messages| errors["rows.#{index}.#{attribute}"] = messages }
      end
      raise ActiveRecord::Rollback if errors.any?
    end
    return redirect_with_errors(new_outline_import_path, errors) if errors.any?

    count = rows.length
    notice = "Saved #{(count == 1) ? "an outline" : "#{count} outlines"}"
    notice += if added.zero?
      ""
    else
      ((added == count) ? ", each a new field" : " (#{added} new #{"field".pluralize(added)})")
    end
    redirect_to setup_path, notice:
  end

  private

  # The row's field, from the group's fields, or a new one under one of the group's systems
  def field_for(row)
    return Current.group.fields.find(row[:field_id]) if row[:field_id].present?
    Current.group.pivots.find(row[:pivot_id]).fields.build(name: row[:name], soil_type_id: row[:soil_type_id],
      area_acres: row[:area_acres].presence)
  end

  def import_params
    params.expect(outline_import: [:use_area, rows: [[:boundary, :field_id, :pivot_id, :name, :soil_type_id, :area_acres]]])
  end
end

# A field's outline page (PLAN.md Phase 8 G.10): the outline drawn on the map, copied from its
# irrigation system's shape or read from a file in the browser, with its acres offered for the
# field's area and the soil survey's dominant soil offered for its soil.
# The outline is for the map and suggestions only; the balance never reads it. A shape that doesn't
# touch its system (G.14 part 7) can move the field to a system it does touch, or to a new Location
# at the shape, with the save.
class FieldOutlinesController < AuthenticatedController
  SYSTEM = [:id, :name, :kind_name, :weather_cell_id, *PivotSerializer::SHAPE].freeze

  def show
    field = Current.group.fields.includes(:soil_type, pivot: :farm, plantings: :plant).find(params[:field_id])
    others = Current.group.fields.includes(:pivot).where.not(id: field.id).where.not(boundary: nil)
    cell = Weather::Grid.cell_for(field.pivot.latitude, field.pivot.longitude)
    render inertia: "Fields/Outline", props: {
      field: FieldSerializer.new(field).to_h,
      pivot: field.pivot.slice(*SYSTEM),
      # Its weather cell's edges, to say whether a Location at the shape would change the weather
      cell: {north: cell.lat_north, south: cell.lat_south, west: cell.lng_west, east: cell.lng_east},
      # The years of its seasons that haven't ended, which follow a move
      open_years: field.plantings.reject(&:ended?).map(&:season_year).uniq.sort,
      # Nearby systems and other fields' outlines, drawn for reference
      other_pivots: Current.group.pivots.where.not(id: field.pivot_id).order(:name).map { |pivot| pivot.slice(*SYSTEM) },
      other_fields: others.map { |other| {id: other.id, name: other.name, boundary: other.boundary} },
      soil_types: SoilTypeSerializer.new(SoilType.order(:field_capacity, :perm_wilting_pt)).to_h,
      from: (params[:from] == "setup") ? "setup" : "field"
    }
  end

  # outline: boundary (GeoJSON as JSON, blank to remove), and optionally area_acres and soil_type_id
  # from the page's offers; and pivot_id to move the field to another system, or new_location=1
  # with latitude and longitude (the shape's center) to move it to a new Location there
  def update
    field = Current.group.fields.includes(pivot: :farm).find(params[:field_id])
    values = outline_params
    field.assign_attributes(values.slice(:area_acres, :soil_type_id).compact_blank)
    field.boundary = values[:boundary] if values.key?(:boundary)
    system = system_for(field, values)
    saved = Field.transaction do
      if system&.new_record? && !system.save
        field.errors.add(:pivot_id, "couldn't be added as a Location: #{system.errors.full_messages.to_sentence}")
        raise ActiveRecord::Rollback
      end
      field.pivot = system if system
      field.save || raise(ActiveRecord::Rollback)
    end
    return redirect_with_errors(field_outline_path(field, from: params[:from]), field.errors.to_hash) unless saved

    destination = (params[:from] == "setup") ? setup_path : field_path(field)
    moved = " and moved it to #{field.pivot.label}" if system
    redirect_to destination, notice: "Saved the shape of #{field.name}#{moved}"
  end

  private

  # The system the field moves to, if it moves: one of the group's, or a new Location (a point
  # system named after the field) on its farm
  def system_for(field, values)
    if values[:pivot_id].present?
      system = Current.group.pivots.find(values[:pivot_id])
      system unless system.id == field.pivot_id
    elsif values[:new_location] == "1"
      field.pivot.farm.pivots.build(kind: "point", name: field.name, latitude: values[:latitude], longitude: values[:longitude])
    end
  end

  def outline_params
    params.expect(outline: [:boundary, :area_acres, :soil_type_id, :pivot_id, :new_location, :latitude, :longitude])
  end
end

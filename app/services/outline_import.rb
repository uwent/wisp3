# Field outlines for many fields at once (PLAN.md Phase 8 G.10): each row's shape goes on one of the
# group's fields (field_id), or makes a new field under one of its systems (pivot_id, name,
# soil_type_id, area_acres). One save, in a transaction: every row saves, or none does. use_area
# also sets existing fields' area from their outlines. Ids outside the group raise RecordNotFound.
class OutlineImport
  # errors: {"rows.2.name" => [messages]} after a failed save
  attr_reader :errors

  def initialize(group, rows, use_area: false)
    @group, @rows, @use_area = group, rows, use_area
    @errors = {}
    @added = 0
  end

  def save
    @errors = {}
    @added = 0
    Field.transaction do
      seen = {}
      @rows.each_with_index do |row, index|
        field = field_for(row)
        if row[:field_id].present? && seen.key?(field.id)
          @errors["rows.#{index}.field_id"] = ["is also in row #{seen[field.id] + 1}"]
          next
        end
        seen[field.id] = index if field.persisted?
        @added += 1 if field.new_record?
        field.boundary = row[:boundary]
        field.area_acres = field.boundary_acres&.round(2) if @use_area && field.persisted? && field.boundary
        next if field.save
        field.errors.to_hash.each { |attribute, messages| @errors["rows.#{index}.#{attribute}"] = messages }
      end
      raise ActiveRecord::Rollback if @errors.any?
    end
    @errors.empty?
  end

  # "Saved 3 field shapes (1 new field)", after a save
  def notice
    count = @rows.length
    notice = "Saved #{(count == 1) ? "a field shape" : "#{count} field shapes"}"
    return notice if @added.zero?
    notice + ((@added == count) ? ", each a new field" : " (#{@added} new #{"field".pluralize(@added)})")
  end

  private

  def field_for(row)
    return @group.fields.find(row[:field_id]) if row[:field_id].present?
    @group.pivots.find(row[:pivot_id]).fields.build(name: row[:name], soil_type_id: row[:soil_type_id],
      area_acres: row[:area_acres].presence)
  end
end

# Irrigation entered once for a pivot, applying to every field under it or to the chosen
# field_ids (D9). Applied when read (DailyInputs); a field's own entry still wins.
class PivotIrrigation < ApplicationRecord
  GALLONS_PER_ACRE_INCH = 27_154

  belongs_to :pivot

  validates :date, presence: true, uniqueness: {scope: :pivot_id}
  validates :inches, :run_hours, numericality: {greater_than_or_equal_to: 0}, allow_nil: true
  validate :amount_given
  validate :fields_under_pivot
  validate :run_hours_convertible, if: -> { inches.nil? && run_hours }

  # Field IDs as submitted by a form, as stored: not sent, or every field under the pivot, means all
  # (NULL). Forms send a blank entry with the checkboxes, so unchecking every one leaves [] (invalid).
  def self.normalize_field_ids(pivot, ids)
    return if ids.nil?
    ids = Array(ids).compact_blank.map(&:to_i)
    (ids.sort == pivot.field_ids.sort) ? nil : ids
  end

  def applies_to?(field) = field.pivot_id == pivot_id && (field_ids.nil? || field_ids.include?(field.id))

  def irrigated_fields
    field_ids.nil? ? pivot.fields : pivot.fields.where(id: field_ids)
  end

  # Inches as entered, or converted from run hours: gpm × minutes over the irrigated area.
  # nil if run hours can't be converted (no pump capacity or field areas).
  def applied_inches
    return inches if inches
    acres = irrigated_acres
    return if pivot.pump_capacity_gpm.nil? || acres.nil?
    pivot.pump_capacity_gpm * run_hours * 60 / (GALLONS_PER_ACRE_INCH * acres)
  end

  # The area watered on the date: the irrigated fields with a planting in season then, each counted
  # at the area its whole-field planting kept for the season (PLAN.md Phase 8 G.9), so a field added
  # later or left fallow doesn't thin the water out. A field growing only part-field plantings that
  # day (G.11) counts whole: the pivot waters the field, not just its plots. A day with no planting
  # counts the fields' areas. nil when an area is missing. Kept per date and fields, as the balance
  # asks once per field under the pivot.
  def irrigated_acres
    key = [date, field_ids]
    @irrigated_acres ||= {}
    return @irrigated_acres[key] if @irrigated_acres.key?(key)
    @irrigated_acres[key] = begin
      fields = irrigated_fields.to_a
      plantings = date ? Planting.on(date).where(field_id: fields.map(&:id)).to_a.group_by(&:field_id) : {}
      areas = if plantings.empty?
        fields.map(&:area_acres)
      else
        fields.filter_map do |field|
          in_season = plantings[field.id] or next
          in_season.find { |planting| !planting.partial? }&.area_acres || field.area_acres
        end
      end
      areas.sum if areas.any? && areas.none?(&:nil?)
    end
  end

  private

  def amount_given
    errors.add(:inches, "or run hours is needed") if inches.nil? && run_hours.nil?
  end

  def fields_under_pivot
    return if field_ids.nil? || pivot.nil?
    errors.add(:field_ids, "must be fields on this pivot") if field_ids.empty? || (field_ids - pivot.field_ids).any?
  end

  def run_hours_convertible
    return if pivot.nil? || applied_inches
    errors.add(:run_hours, "can be used only when the pivot's pump capacity and the field areas are set; enter inches instead")
  end
end

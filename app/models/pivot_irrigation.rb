# Irrigation entered once for a pivot, applying to every field under it or to the chosen
# field_ids (D9). Applied when read (DailyInputs); a field's own entry still wins. "Under it" means
# on it that day (Pivot#fields_on): a season keeps the system it ran on, so a field moved to
# another system keeps this one's irrigation for its earlier seasons (G.14 part 7).
class PivotIrrigation < ApplicationRecord
  GALLONS_PER_ACRE_INCH = 27_154

  belongs_to :pivot

  validates :date, presence: true, uniqueness: {scope: :pivot_id}
  validates :inches, :run_hours, numericality: {greater_than_or_equal_to: 0}, allow_nil: true
  validate :amount_given
  validate :fields_under_pivot
  validate :run_hours_convertible, if: -> { inches.nil? && run_hours }

  # Field IDs as submitted by a form, as stored: not sent, or every field on the pivot that day,
  # means all (NULL). Forms send a blank entry with the checkboxes, so unchecking every one leaves []
  # (invalid).
  def self.normalize_field_ids(pivot, ids, date)
    return if ids.nil?
    ids = Array(ids).compact_blank.map(&:to_i)
    (date && ids.sort == pivot.fields_on(date).map(&:id).sort) ? nil : ids
  end

  # Whether the field is among those it was applied to
  def covers?(field_id) = field_ids.nil? || field_ids.include?(field_id)

  # Inches as entered, or converted from run hours: gpm × minutes over the irrigated area.
  # nil if run hours can't be converted (no pump capacity or field areas).
  def applied_inches
    return inches if inches
    acres = irrigated_acres
    return if pivot.pump_capacity_gpm.nil? || acres.nil?
    pivot.pump_capacity_gpm * run_hours * 60 / (GALLONS_PER_ACRE_INCH * acres)
  end

  # The area watered on the date: the irrigated fields with a planting in season then on this system
  # (a season keeps the system it ran on, G.14 part 7), each counted at the area its whole-field
  # planting kept for the season (PLAN.md Phase 8 G.9), so a field added later or left fallow
  # doesn't thin the water out. A field growing only part-field plantings that day (G.11) counts
  # whole: the pivot waters the field, not just its plots. A day with no planting counts the
  # system's fields' areas. nil when an area is missing. Kept per date and fields, as the balance
  # asks once per field under the pivot.
  def irrigated_acres
    key = [date, field_ids]
    @irrigated_acres ||= {}
    return @irrigated_acres[key] if @irrigated_acres.key?(key)
    @irrigated_acres[key] = begin
      plantings = date ? pivot.plantings.on(date).includes(:field).select { |planting| covers?(planting.field_id) } : []
      areas = if plantings.empty?
        pivot.fields.select { |field| covers?(field.id) }.map(&:area_acres)
      else
        plantings.group_by(&:field).map do |field, in_season|
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

  # The fields on the system that day; a field it already named stays allowed, so an earlier
  # irrigation can be edited after a field has moved
  def fields_under_pivot
    return if field_ids.nil? || pivot.nil?
    allowed = (date ? pivot.fields_on(date).map(&:id) : pivot.field_ids) + Array(field_ids_in_database)
    errors.add(:field_ids, "must be fields on this system that day") if field_ids.empty? || (field_ids - allowed).any?
  end

  def run_hours_convertible
    return if pivot.nil? || applied_inches
    errors.add(:run_hours, "can be used only when the pivot's pump capacity and the field areas are set; enter inches instead")
  end
end

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
    acres = irrigated_fields.map(&:area_acres)
    return if pivot.pump_capacity_gpm.nil? || acres.empty? || acres.any?(&:nil?)
    pivot.pump_capacity_gpm * run_hours * 60 / (GALLONS_PER_ACRE_INCH * acres.sum)
  end

  private

  def amount_given
    errors.add(:inches, "or run hours must be entered") if inches.nil? && run_hours.nil?
  end

  def fields_under_pivot
    return if field_ids.nil? || pivot.nil?
    errors.add(:field_ids, "must be fields under this pivot") if field_ids.empty? || (field_ids - pivot.field_ids).any?
  end

  def run_hours_convertible
    return if pivot.nil? || applied_inches
    errors.add(:run_hours, "need the pivot's pump capacity and the field areas; enter inches instead")
  end
end

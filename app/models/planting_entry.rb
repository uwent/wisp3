# A part-field planting's own entries for a day (PLAN.md Phase 8 G.11): irrigation applied to it
# alone (a drip zone, a plot watered by hand), a soil moisture reading from a sensor in it, and
# notes. They come before the field's entries for its balance (DailyInputs); rain stays on the
# field. Only plantings on part of a field have them: a whole-field planting is the field.
class PlantingEntry < ApplicationRecord
  def self.entry_values = %i[irrigation_in soil_moisture_pct notes].freeze

  include DailyEntry

  belongs_to :planting

  validates :date, uniqueness: {scope: :planting_id}
  validate :part_field_planting

  private

  def part_field_planting
    return if planting.nil? || planting.partial?
    errors.add(:base, "Only a planting on part of a field has its own entries; enter the field's instead")
  end
end

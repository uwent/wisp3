# Irrigation entered once for a pivot, applying to every field under it or to the chosen
# field_ids (D9). Applied when read (DailyInputs); a field's own entry still wins. "Under it" means
# on it that day (Pivot#fields_on): a season keeps the system it ran on, so a field moved to
# another system keeps this one's irrigation for its earlier seasons (G.14 part 7).
class PivotIrrigation < ApplicationRecord
  GALLONS_PER_ACRE_INCH = 27_154
  # What a form sends for the amount: one of inches, run hours or the percent timer's setting (with
  # the circles it ran), the others blank
  AMOUNTS = %i[inches run_hours percent_timer circles].freeze

  belongs_to :pivot

  validates :date, presence: true, uniqueness: {scope: :pivot_id}
  validates :inches, :run_hours, numericality: {greater_than_or_equal_to: 0}, allow_nil: true
  validates :percent_timer, numericality: {greater_than: 0, less_than_or_equal_to: 100,
                                           message: "must be more than 0 and at most 100"}, allow_nil: true
  validates :circles, numericality: {greater_than: 0}, allow_nil: true
  validate :amount_given
  validate :fields_under_pivot
  validate :run_hours_convertible, if: -> { inches.nil? && percent_timer.nil? && run_hours }
  validate :percent_convertible, if: -> { inches.nil? && percent_timer }

  # Circles belong to a percent; one is the default, stored as NULL
  normalizes :circles, with: ->(circles) { (circles == 1) ? nil : circles }
  before_validation -> { self.circles = nil }, unless: :percent_timer

  # Field IDs as submitted by a form, as stored: not sent, or every field on the pivot that day,
  # means all (NULL). Forms send a blank entry with the checkboxes, so unchecking every one leaves []
  # (invalid).
  def self.normalize_field_ids(pivot, ids, date)
    return if ids.nil?
    ids = Array(ids).compact_blank.map(&:to_i)
    (date && ids.sort == pivot.fields_on(date).map(&:id).sort) ? nil : ids
  end

  # Loads what converting run hours reads (irrigated_acres: the system's fields and plantings), once
  # per system rather than about three queries per irrigation. Returns the irrigations.
  def self.preload_areas(irrigations)
    irrigations = irrigations.to_a
    ActiveRecord::Associations::Preloader.new(records: irrigations.select(&:run_hours),
      associations: {pivot: [:fields, {plantings: :field}]}).call
    irrigations
  end

  # Whether the field is among those it was applied to
  def covers?(field_id) = field_ids.nil? || field_ids.include?(field_id)

  # How it was entered: :inches, :percent (the percent timer's setting) or :hours. A form sends one
  # and blanks the others.
  def entered_as
    return :inches if inches
    percent_timer ? :percent : :hours
  end

  # Inches as entered; from the percent timer, the system's depth at 100% × 100 ÷ percent for each
  # circle (or pass); or converted from run hours: gpm × minutes over the irrigated area. nil if it
  # can't be converted (no depth at 100%; no pump capacity or field areas).
  def applied_inches
    return inches if inches
    return pivot.inches_at_percent(percent_timer, circles) if percent_timer
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
  # asks once per field under the pivot. Reads the pivot's plantings and fields as loaded when they
  # are (DailyInputs.preload), else queries them.
  def irrigated_acres
    key = [date, field_ids]
    @irrigated_acres ||= {}
    return @irrigated_acres[key] if @irrigated_acres.key?(key)
    @irrigated_acres[key] = begin
      plantings = date ? plantings_on(date).select { |planting| covers?(planting.field_id) } : []
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

  def plantings_on(date)
    return pivot.plantings.on(date).includes(:field) unless pivot.plantings.loaded?
    pivot.plantings.select { |planting| planting.season_range.cover?(date) }
  end

  def amount_given
    errors.add(:inches, "or run hours is needed") if inches.nil? && run_hours.nil? && percent_timer.nil?
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

  def percent_convertible
    return if pivot.nil? || pivot.percent_timer?
    errors.add(:percent_timer, "can be used only when the system's depth at 100% is set; enter inches instead")
  end
end

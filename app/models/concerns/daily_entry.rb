# What a grower records for a day: rain, irrigation, a soil moisture reading, notes. NULL means
# not entered and 0.0 means entered as zero (legacy stored 0.00001 to tell them apart, C5).
# A model can keep fewer of them by defining entry_values before including this (PlantingEntry has
# no rain: rain falls on the whole field).
module DailyEntry
  extend ActiveSupport::Concern

  # irrigation_pct (a field's only, FieldEntry): the percent timer's setting irrigation_in came from,
  # kept to show it as entered (docs/plans/phase-9.md §8)
  VALUES = %i[rain_in irrigation_in irrigation_pct soil_moisture_pct notes].freeze
  # What a day ahead takes: planned irrigation and notes; rain and readings haven't happened yet
  FUTURE_VALUES = %i[irrigation_in irrigation_pct notes].freeze

  included do
    validates :date, presence: true
    depths = entry_values & %i[rain_in irrigation_in]
    validates(*depths, numericality: {greater_than_or_equal_to: 0}, allow_nil: true) if depths.any?
    validates :soil_moisture_pct, numericality: {in: 0..100, message: "must be between 0 and 100"}, allow_nil: true
    # What a grower enters (record); seeds may write a season ahead of today
    validate :nothing_measured_ahead, on: :entry

    normalizes :notes, with: ->(notes) { notes.strip.presence }
  end

  class_methods do
    def entry_values = VALUES

    # Sets values (any of entry_values) on the scope's entry for date, creating it if needed, and
    # deletes the entry once nothing is left in it. Returns the entry; check errors if invalid.
    def record(scope, date, values)
      entry = scope.find_or_initialize_by(date:)
      values = values.to_h.symbolize_keys.slice(*entry_values)
      entry.assign_attributes(values)
      # Inches typed some other way replace the percent they came from
      if entry_values.include?(:irrigation_pct) && !values.key?(:irrigation_pct) && entry.irrigation_in_changed?
        entry.irrigation_pct = nil
      end
      if entry.nothing_entered?
        entry.destroy! if entry.persisted?
      else
        entry.save(context: :entry)
      end
      entry
    end
  end

  def nothing_entered? = self.class.entry_values.all? { |attribute| self[attribute].nil? }

  private

  # Checked as values change, for every way a grower enters them (the field grid, daily entry);
  # ahead of the day the pages show (Current.today), as the forms offer
  def nothing_measured_ahead
    return unless date && date > Current.today
    (self.class.entry_values - FUTURE_VALUES).each do |attribute|
      next if self[attribute].nil? || !will_save_change_to_attribute?(attribute)
      errors.add(attribute, "can't be entered for a future date; only planned irrigation and notes can")
    end
  end
end

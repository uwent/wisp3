# What a grower records for a day: rain, irrigation, a soil moisture reading, notes. NULL means
# not entered and 0.0 means entered as zero (legacy stored 0.00001 to tell them apart, C5).
module DailyEntry
  extend ActiveSupport::Concern

  VALUES = %i[rain_in irrigation_in soil_moisture_pct notes].freeze

  included do
    validates :date, presence: true
    validates :rain_in, :irrigation_in, numericality: {greater_than_or_equal_to: 0}, allow_nil: true
    validates :soil_moisture_pct, numericality: {in: 0..100, message: "must be between 0 and 100"}, allow_nil: true

    normalizes :notes, with: ->(notes) { notes.strip.presence }
  end

  class_methods do
    # Sets values (any of VALUES) on the scope's entry for date, creating it if needed, and
    # deletes the entry once nothing is left in it. Returns the entry; check errors if invalid.
    def record(scope, date, values)
      entry = scope.find_or_initialize_by(date:)
      entry.assign_attributes(values.to_h.symbolize_keys.slice(*VALUES))
      if entry.nothing_entered?
        entry.destroy! if entry.persisted?
      else
        entry.save
      end
      entry
    end
  end

  def nothing_entered? = VALUES.all? { |attribute| self[attribute].nil? }
end

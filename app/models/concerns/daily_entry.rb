# What a grower records for a day: rain, irrigation, a soil moisture reading, notes. NULL means
# not entered and 0.0 means entered as zero (legacy stored 0.00001 to tell them apart, C5).
module DailyEntry
  extend ActiveSupport::Concern

  included do
    validates :date, presence: true
    validates :rain_in, :irrigation_in, numericality: {greater_than_or_equal_to: 0}, allow_nil: true
    validates :soil_moisture_pct, numericality: {in: 0..100}, allow_nil: true
  end
end

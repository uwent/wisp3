class FieldEntry < ApplicationRecord
  include DailyEntry

  belongs_to :field

  validates :date, uniqueness: {scope: :field_id}
  validates :irrigation_pct, numericality: {greater_than: 0, less_than_or_equal_to: 100,
                                            message: "must be more than 0 and at most 100"}, allow_nil: true
end

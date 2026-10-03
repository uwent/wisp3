class FieldEntry < ApplicationRecord
  include DailyEntry

  belongs_to :field

  validates :date, uniqueness: {scope: :field_id}
end

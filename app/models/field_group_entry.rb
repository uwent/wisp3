class FieldGroupEntry < ApplicationRecord
  include DailyEntry

  belongs_to :field_group

  validates :date, uniqueness: {scope: :field_group_id}
end

# Fields that share data entry (e.g. one rain gauge). Its entries apply to member fields when
# read, below their own entries and pivot irrigation (DailyInputs).
class FieldGroup < ApplicationRecord
  belongs_to :group
  has_many :field_group_members, dependent: :destroy
  has_many :fields, through: :field_group_members
  has_many :field_group_entries, dependent: :destroy

  validates :name, presence: true, length: {maximum: 100}
end

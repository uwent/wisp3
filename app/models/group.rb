# A farm operation: the unit of data ownership. Every farm, pivot and field belongs to a group,
# and users reach them only through their memberships (see Current.group).
class Group < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships

  validates :name, presence: true, length: {maximum: 100}
end

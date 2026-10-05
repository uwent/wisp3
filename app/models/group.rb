# A farm operation: the unit of data ownership. Every farm, pivot and field belongs to a group,
# and users reach them only through their memberships (see Current.group).
class Group < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :farms, dependent: :destroy
  has_many :pivots, through: :farms
  has_many :fields, through: :pivots
  has_many :field_groups, dependent: :destroy
  has_many :digest_exclusions, as: :subject, dependent: :delete_all

  # Plantings of this group's fields, for scoping lookups by ID
  def plantings = Planting.joins(field: {pivot: :farm}).where(farms: {group_id: id})

  validates :name, presence: true, length: {maximum: 100}
end

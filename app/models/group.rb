# A farm operation: the unit of data ownership. Every farm, system and field belongs to a group,
# and users reach them only through their memberships (see Current.group).
class Group < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :farms, dependent: :destroy
  has_many :systems, through: :farms
  has_many :irrigation_groups, through: :farms
  has_many :fields, through: :systems
  has_many :digest_exclusions, as: :subject, dependent: :delete_all

  # Plantings of this group's fields, for scoping lookups by ID
  def plantings = Planting.joins(field: {system: :farm}).where(farms: {group_id: id})

  validates :name, presence: true, length: {maximum: 100}
  normalizes_name :name

  # The public example farm: at most one group, with no members, shown read-only to
  # anyone (example mode, ExampleMode) as of its example_as_of; rebuilt by bin/rails demo:example
  scope :examples, -> { where.not(example_as_of: nil) }

  def self.example = examples.first
end

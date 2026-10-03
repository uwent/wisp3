# A soil texture's default water-holding fractions (reference data, db/reference/soil_types.yml)
class SoilType < ApplicationRecord
  DEFAULT_KEY = "sandy_loam"

  has_many :fields, dependent: :restrict_with_exception

  validates :key, :name, presence: true
  validates :key, uniqueness: true
  validates :field_capacity, :perm_wilting_pt, numericality: {greater_than: 0, less_than: 0.6}

  def self.default = find_by!(key: DEFAULT_KEY)
end

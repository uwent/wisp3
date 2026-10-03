# A crop (reference data, db/reference/plants.yml)
class Plant < ApplicationRecord
  has_many :plantings, dependent: :restrict_with_exception

  validates :key, :name, presence: true
  validates :key, uniqueness: true
  validates :default_max_root_zone_depth, numericality: {greater_than: 0}
  validates :canopy_model, inclusion: {in: ->(_) { CanopyModel::CURVES.keys }}, allow_nil: true
end

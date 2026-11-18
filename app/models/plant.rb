# A crop (reference data, db/reference/plants.yml)
class Plant < ApplicationRecord
  has_many :plantings, dependent: :restrict_with_exception

  validates :key, :name, presence: true
  validates :key, uniqueness: true
  validates :default_max_root_zone_depth, numericality: {greater_than: 0}
  # FAO-56 Table 12 (C21): the crop coefficient at full cover and the crop's height
  validates :kc_mid, numericality: {greater_than: 0, less_than: 2}
  validates :crop_height_m, numericality: {greater_than: 0, less_than: 10}
  validates :canopy_model, inclusion: {in: ->(_) { CanopyModel::CURVES.keys }}, allow_nil: true
end

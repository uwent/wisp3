# A crop (reference data, db/reference/plants.yml)
class Plant < ApplicationRecord
  has_many :plantings, dependent: :restrict_with_exception

  validates :key, :name, presence: true
  validates :key, uniqueness: true
  validates :default_max_root_zone_depth, numericality: {greater_than: 0}
  # FAO-56 Rev.1 Tables 6.1–6.4 (C21, C25): the crop coefficient at full cover and the crop's height
  validates :kc_mid, numericality: {greater_than: 0, less_than: 2}
  validates :crop_height_m, numericality: {greater_than: 0, less_than: 10}
  # FAO-56 Rev.1 Tables 7.1–7.2 (C22, C25): the basal crop coefficient at full cover, mid season and harvest
  validates :kcb_mid, :kcb_end, numericality: {greater_than: 0, less_than: 2}, allow_nil: true
  validates :canopy_model, inclusion: {in: ->(_) { CanopyModel::CURVES.keys }}, allow_nil: true
end

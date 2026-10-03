class Pivot < ApplicationRecord
  # The US and Canada for now (Hawaii to the Arctic, Alaska to Newfoundland). Open-Meteo is
  # global, so this can widen; it also catches swapped or unsigned coordinates.
  LATITUDES = 18.0..84.0
  LONGITUDES = -180.0..-52.0

  belongs_to :farm
  has_many :fields, dependent: :destroy
  has_many :pivot_irrigations, dependent: :destroy

  validates :name, presence: true, length: {maximum: 100}
  validates :latitude, presence: true, numericality: {in: LATITUDES, message: "must be in the US or Canada"}
  validates :longitude, presence: true, numericality: {in: LONGITUDES, message: "must be in the US or Canada"}
  validates :radius_ft, :pump_capacity_gpm, numericality: {greater_than: 0}, allow_nil: true
  validates :arc_start_deg, :arc_end_deg, numericality: {in: 0..360}, allow_nil: true
  validate :arc_complete

  private

  def arc_complete
    errors.add(:arc_end_deg, "is needed with a start angle") if arc_start_deg && !arc_end_deg
    errors.add(:arc_start_deg, "is needed with an end angle") if arc_end_deg && !arc_start_deg
  end
end

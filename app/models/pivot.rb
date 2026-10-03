class Pivot < ApplicationRecord
  # Pivots must be in or near Wisconsin, which also catches swapped or unsigned coordinates
  LATITUDES = 41.0..48.5
  LONGITUDES = -97.5..-82.0

  belongs_to :farm
  has_many :fields, dependent: :destroy
  has_many :pivot_irrigations, dependent: :destroy

  validates :name, presence: true, length: {maximum: 100}
  validates :latitude, presence: true, numericality: {in: LATITUDES, message: "must be in or near Wisconsin"}
  validates :longitude, presence: true, numericality: {in: LONGITUDES, message: "must be in or near Wisconsin"}
  validates :radius_ft, :pump_capacity_gpm, numericality: {greater_than: 0}, allow_nil: true
  validates :arc_start_deg, :arc_end_deg, numericality: {in: 0..360}, allow_nil: true
  validate :arc_complete

  private

  def arc_complete
    errors.add(:arc_end_deg, "is needed with a start angle") if arc_start_deg && !arc_end_deg
    errors.add(:arc_start_deg, "is needed with an end angle") if arc_end_deg && !arc_start_deg
  end
end

# A canopy reading (percent cover, or LAI) for a planting; Canopy interpolates between them
class CanopyObservation < ApplicationRecord
  belongs_to :planting

  validates :date, presence: true, uniqueness: {scope: :planting_id}
  validates :pct_cover, numericality: {in: 0..100, message: "must be between 0 and 100"}, allow_nil: true
  validates :lai, numericality: {greater_than_or_equal_to: 0}, allow_nil: true
  validate :exactly_one_value

  private

  def exactly_one_value
    errors.add(:base, "Enter either percent cover or LAI") unless [pct_cover, lai].compact.size == 1
  end
end

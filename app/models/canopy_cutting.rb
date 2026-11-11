# A cutting of a perennial planting (alfalfa, mint; one on the perennial regrowth curve, PLAN.md
# Phase 8 G.3): the canopy drops to stubble that day and regrows (CutCanopy), so the season is a
# sawtooth rather than one curve.
class CanopyCutting < ApplicationRecord
  belongs_to :planting

  validates :date, presence: true, uniqueness: {scope: :planting_id, message: "already has a cutting"}
  validate :within_season
  validate :perennial

  # Plantings on this curve take cuttings
  CURVE = "perennial_regrowth"

  private

  def within_season
    return unless date && planting
    errors.add(:date, "must be after emergence (green-up)") if date <= planting.emergence_date
    errors.add(:date, "must be within the season") if date > planting.end_date
  end

  def perennial
    return unless planting && planting.cover_curve&.key != CURVE
    errors.add(:base, "Only a planting on the perennial regrowth curve (alfalfa, mint) can be cut")
  end
end

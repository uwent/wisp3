# One crop on one field for one season. Plantings on a field can't overlap, which allows double
# cropping (legacy picked the crop with the latest emergence, C10).
class Planting < ApplicationRecord
  ET_METHODS = %w[pct_cover lai].freeze
  CANOPY_INTERPOLATIONS = %w[linear curve].freeze
  DEFAULT_MAD_FRAC = 0.5

  belongs_to :field
  belongs_to :plant
  has_many :canopy_observations, -> { order(:date) }, dependent: :destroy

  validates :season_start, :emergence_date, :end_date, presence: true
  validates :max_root_zone_depth, numericality: {greater_than: 0}
  validates :mad_frac, numericality: {in: 0.05..0.95, message: "must be between 5% and 95%"}
  validates :et_method, inclusion: {in: ET_METHODS}
  validates :canopy_interpolation, inclusion: {in: CANOPY_INTERPOLATIONS}, allow_nil: true
  validates :target_ad_pct, :initial_moisture_pct, numericality: {in: 0..100, message: "must be between 0 and 100"},
    allow_nil: true
  validate :dates_in_order
  validate :lai_needs_curve
  validate :no_overlap, if: -> { field && season_start && end_date }

  normalizes :variety, :notes, with: ->(text) { text.strip.presence }
  normalizes :canopy_interpolation, with: ->(value) { value.presence }

  # Only crops that are vine killed keep a vine kill date, so changing the crop leaves none behind
  before_validation { self.vine_kill_date = nil unless vine_kill_crop? }

  scope :in_season, ->(year) { where(season_start: Date.new(year).all_year) }

  # Defaults for a new planting of plant in year: Apr 1 to Nov 30, as in legacy WISP
  def self.defaults_for(plant, year)
    {
      season_start: Date.new(year, 4, 1),
      emergence_date: Date.new(year, 5, 1),
      end_date: Date.new(year, 11, 30),
      max_root_zone_depth: plant.default_max_root_zone_depth,
      mad_frac: DEFAULT_MAD_FRAC,
      et_method: "pct_cover"
    }
  end

  # Whether the crop takes a vine kill date (potato; canopy_curves.yml)
  def vine_kill_crop? = plant.present? && CanopyCurve.for(plant.key)&.vine_kill? || false

  # Whether the crop has a canopy curve for this planting's method (CanopyCurve, or CanopyModel for LAI)
  def canopy_curve? = (et_method == "lai") ? plant.canopy_model.present? : CanopyCurve.for(plant.key).present?

  # How readings combine with the curve: the setting, or the curve where there is one
  def effective_canopy_interpolation = canopy_curve? ? (canopy_interpolation || "curve") : "linear"

  def season_range = season_start..end_date
  def season_year = season_start.year

  private

  # LAI is offered only for crops with an LAI growth curve (PLAN.md Phase 6.7): deriving LAI from
  # percent cover gave 20–40% less ET than the percent cover method (docs/canopy/03-crop-curves.md)
  def lai_needs_curve
    return unless et_method == "lai" && plant && plant.canopy_model.nil?
    errors.add(:et_method, "can be LAI (leaf area index) only for crops that have an LAI growth curve (#{lai_crops})")
  end

  def lai_crops = Plant.where.not(canopy_model: nil).order(:name).pluck(:name).to_sentence.presence || "none yet"

  def dates_in_order
    return unless season_start && emergence_date && end_date
    errors.add(:end_date, "must be on or after the season start") if end_date < season_start
    errors.add(:end_date, "must be on or after emergence") if end_date < emergence_date
    return unless vine_kill_date
    errors.add(:vine_kill_date, "must be on or after emergence") if vine_kill_date < emergence_date
    errors.add(:vine_kill_date, "must be on or before the harvest date") if vine_kill_date > end_date
  end

  def no_overlap
    overlapping = Planting.where(field_id:).where.not(id:)
      .where("season_start <= ? AND end_date >= ?", end_date, season_start)
    errors.add(:season_start, "overlaps another planting on this field") if overlapping.exists?
  end
end

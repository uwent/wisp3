# One crop on one field for one season. Plantings on a field can't overlap, which allows double
# cropping (legacy picked the crop with the latest emergence, C10).
class Planting < ApplicationRecord
  ET_METHODS = %w[pct_cover lai].freeze
  DEFAULT_MAD_FRAC = 0.5

  belongs_to :field
  belongs_to :plant
  has_many :canopy_observations, -> { order(:date) }, dependent: :destroy

  validates :season_start, :emergence_date, :end_date, presence: true
  validates :max_root_zone_depth, numericality: {greater_than: 0}
  validates :mad_frac, numericality: {in: 0.05..0.95}
  validates :et_method, inclusion: {in: ET_METHODS}
  validates :target_ad_pct, :initial_moisture_pct, numericality: {in: 0..100}, allow_nil: true
  validate :dates_in_order
  validate :no_overlap, if: -> { field && season_start && end_date }

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

  def season_range = season_start..end_date
  def season_year = season_start.year

  private

  def dates_in_order
    return unless season_start && emergence_date && end_date
    errors.add(:end_date, "must be on or after the season start") if end_date < season_start
    errors.add(:end_date, "must be on or after emergence") if end_date < emergence_date
  end

  def no_overlap
    overlapping = Planting.where(field_id:).where.not(id:)
      .where("season_start <= ? AND end_date >= ?", end_date, season_start)
    errors.add(:season_start, "overlaps another planting on this field") if overlapping.exists?
  end
end

# One crop on one field for one season. Plantings on a field can't overlap, which allows double
# cropping (legacy picked the crop with the latest emergence, C10).
#
# A planting keeps the values its balance runs on (PLAN.md Phase 8 G.9): the field's soil type and
# its own field capacity and wilting point (NULL follows the soil type, as on fields), the field's
# area, and the pivot's weather cell. They're copied when the planting is created; editing the
# field or moving the pivot changes them on plantings that haven't ended (Field, Pivot), so earlier
# seasons keep what they ran with.
class Planting < ApplicationRecord
  ET_METHODS = %w[pct_cover lai].freeze
  CANOPY_INTERPOLATIONS = %w[linear curve].freeze
  DEFAULT_MAD_FRAC = 0.5

  belongs_to :field
  belongs_to :plant
  belongs_to :soil_type
  belongs_to :weather_cell, optional: true
  has_many :canopy_observations, -> { order(:date) }, dependent: :destroy

  validates :season_start, :emergence_date, :end_date, presence: true
  validates :max_root_zone_depth, numericality: {greater_than: 0}
  validates :mad_frac, numericality: {in: 0.05..0.95, message: "must be between 5% and 95%"}
  validates :et_method, inclusion: {in: ET_METHODS}
  validates :canopy_interpolation, inclusion: {in: CANOPY_INTERPOLATIONS}, allow_nil: true
  validates :field_capacity, :perm_wilting_pt, numericality: {greater_than: 0, less_than: 0.6}, allow_nil: true
  validates :area_acres, numericality: {greater_than: 0}, allow_nil: true
  validates :target_ad_pct, :initial_moisture_pct, numericality: {in: 0..100, message: "must be between 0 and 100"},
    allow_nil: true
  validate :dates_in_order
  validate :lai_needs_curve
  validate :wilting_point_below_capacity
  validate :no_overlap, if: -> { field && season_start && end_date }

  normalizes :variety, :notes, with: ->(text) { text.strip.presence }
  normalizes :canopy_interpolation, with: ->(value) { value.presence }

  # Only crops that are vine killed keep a vine kill date, so changing the crop leaves none behind
  before_validation { self.vine_kill_date = nil unless vine_kill_crop? }
  # Before validation (soil type is required) and again on create, for saves that skip validation
  before_validation :copy_from_field, on: :create
  before_create :copy_from_field

  scope :in_season, ->(year) { where(season_start: Date.new(year).all_year) }
  # Plantings whose season hasn't ended: they follow edits to their field and pivot
  scope :open, ->(today = Date.current) { where(end_date: today..) }
  # Plantings whose season includes date
  scope :on, ->(date) { where(season_start: ..date, end_date: date..) }

  # The field values a planting copies, with the field's attribute for each
  FIELD_VALUES = %i[soil_type_id field_capacity perm_wilting_pt area_acres].freeze

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

  # NULL means "use the soil type's value" (C14)
  def effective_field_capacity = field_capacity || soil_type.field_capacity
  def effective_perm_wilting_pt = perm_wilting_pt || soil_type.perm_wilting_pt

  def ended?(today = Date.current) = end_date < today

  def season_range = season_start..end_date
  def season_year = season_start.year

  private

  # A new planting takes its field's soil and area, unless given its own soil type (with its
  # overrides) or area, and its pivot's weather cell
  def copy_from_field
    return unless field
    if soil_type.nil?
      self.soil_type = field.soil_type
      self.field_capacity = field.field_capacity if field_capacity.nil?
      self.perm_wilting_pt = field.perm_wilting_pt if perm_wilting_pt.nil?
    end
    self.area_acres ||= field.area_acres
    self.weather_cell ||= field.pivot&.weather_cell
  end

  def wilting_point_below_capacity
    return unless soil_type
    unless effective_perm_wilting_pt < effective_field_capacity
      errors.add(:perm_wilting_pt, "must be below field capacity")
    end
  end

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

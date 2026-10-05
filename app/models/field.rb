class Field < ApplicationRecord
  belongs_to :pivot
  belongs_to :soil_type
  has_one :farm, through: :pivot
  has_many :plantings, -> { order(:season_start) }, dependent: :destroy
  has_many :field_entries, dependent: :destroy
  has_many :field_group_members, dependent: :destroy
  has_many :field_groups, through: :field_group_members
  has_many :digest_exclusions, as: :subject, dependent: :delete_all

  validates :name, presence: true, length: {maximum: 100}
  validates :area_acres, numericality: {greater_than: 0}, allow_nil: true
  validates :field_capacity, :perm_wilting_pt, numericality: {greater_than: 0, less_than: 0.6}, allow_nil: true
  validate :wilting_point_below_capacity

  normalizes :notes, with: ->(text) { text.strip.presence }

  # NULL means "use the soil type's value" (C14)
  def effective_field_capacity = field_capacity || soil_type.field_capacity
  def effective_perm_wilting_pt = perm_wilting_pt || soil_type.perm_wilting_pt

  # The planting whose season includes date, if any
  def planting_on(date)
    plantings.find { |planting| planting.season_range.cover?(date) }
  end

  private

  def wilting_point_below_capacity
    return unless soil_type
    unless effective_perm_wilting_pt < effective_field_capacity
      errors.add(:perm_wilting_pt, "must be below field capacity")
    end
  end
end

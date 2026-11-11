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
  validate :pivot_kept_with_history, on: :update

  normalizes :notes, with: ->(text) { text.strip.presence }

  # Plantings that haven't ended follow the field's soil, area and pivot (PLAN.md Phase 8 G.9);
  # ended ones keep what their season ran with
  after_update :update_open_plantings

  # Whether the field has plantings whose season has ended (they stay on its pivot, G.9)
  def history? = plantings.any?(&:ended?)

  # NULL means "use the soil type's value" (C14)
  def effective_field_capacity = field_capacity || soil_type.field_capacity
  def effective_perm_wilting_pt = perm_wilting_pt || soil_type.perm_wilting_pt

  # Whether the balance uses modeled rain where nothing is entered: the field's setting, NULL
  # following its group's (Q7). Either way the projection uses forecast rain (DailyInputs).
  def effective_use_model_precip
    use_model_precip.nil? ? pivot.farm.group.use_model_precip : use_model_precip
  end

  # The planting whose season includes date, if any: the whole-field one, else the first part-field
  # one (a field can have several of those at once, G.11; plantings_on gives them all)
  def planting_on(date)
    plantings_on(date).min_by { |planting| [planting.partial? ? 1 : 0, planting.season_start, planting.id] }
  end

  # Every planting whose season includes date
  def plantings_on(date)
    plantings.select { |planting| planting.season_range.cover?(date) }
  end

  private

  def update_open_plantings
    changed = Planting::FIELD_VALUES.select { |attribute| saved_change_to_attribute?(attribute) }
    values = changed.to_h { |attribute| [attribute, self[attribute]] }
    values[:weather_cell_id] = pivot.weather_cell_id if saved_change_to_pivot_id?
    soil = values.slice(:soil_type_id, :field_capacity, :perm_wilting_pt)
    # Plots on their own soil keep it (G.11)
    plantings.open.where(own_soil: false).update_all(soil) if soil.any?
    plantings.open.update_all(values.slice(:weather_cell_id)) if values.key?(:weather_cell_id)
    # Part-field plantings keep their own area (G.11)
    plantings.open.where(partial: false).update_all(area_acres:) if values.key?(:area_acres)
  end

  # Earlier seasons' pivot irrigation and weather belong to the pivot the field was on, so a field
  # with them stays; the setup form offers a new field under the other pivot instead (G.9)
  def pivot_kept_with_history
    return unless will_save_change_to_pivot_id? && history?
    errors.add(:pivot_id, "can't change for a field with earlier seasons, which stay with its pivot. " \
      "Set up a new field under the other pivot instead")
  end

  def wilting_point_below_capacity
    return unless soil_type
    unless effective_perm_wilting_pt < effective_field_capacity
      errors.add(:perm_wilting_pt, "must be below field capacity")
    end
  end
end

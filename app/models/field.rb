class Field < ApplicationRecord
  belongs_to :pivot
  belongs_to :soil_type
  has_one :farm, through: :pivot
  has_many :plantings, -> { order(:season_start, :id) }, dependent: :destroy
  has_many :field_entries, dependent: :destroy
  has_many :digest_exclusions, as: :subject, dependent: :delete_all

  validates :name, presence: true, length: {maximum: 100}
  validates :area_acres, numericality: {greater_than: 0}, allow_nil: true
  validates :field_capacity, :perm_wilting_pt, numericality: {greater_than: 0, less_than: 0.6}, allow_nil: true
  validate :wilting_point_below_capacity
  validate :boundary_readable

  normalizes :notes, with: ->(text) { text.strip.presence }

  # Plantings that haven't ended follow the field's soil, area and system (PLAN.md Phase 8 G.9, G.14
  # part 7); ended ones keep what their season ran with, so a field can move at any time
  after_update :update_open_plantings

  # The outline (G.10, G.14): a GeoJSON Polygon with one ring, or nil. A JSON string is parsed and
  # blank clears it; positions are rounded (FieldBoundary.normalize).
  def boundary=(value)
    super(value.blank? ? nil : FieldBoundary.normalize(value))
  end

  # The outline's area in acres, or nil without one. Offered for area_acres, never copied to it.
  def boundary_acres = boundary && FieldBoundary.acres(boundary)

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

  # The irrigation system the field was on that day: its planting's (a season keeps the system it
  # ran on, G.14 part 7), else, with nothing planted, the one it's on now
  def pivot_id_on(date) = planting_on(date)&.pivot_id || pivot_id

  private

  def update_open_plantings
    changed = Planting::FIELD_VALUES.select { |attribute| saved_change_to_attribute?(attribute) }
    values = changed.to_h { |attribute| [attribute, self[attribute]] }
    if saved_change_to_pivot_id?
      values[:pivot_id] = pivot_id
      values[:weather_cell_id] = pivot.weather_cell_id
    end
    soil = values.slice(:soil_type_id, :field_capacity, :perm_wilting_pt)
    # Plots on their own soil keep it (G.11)
    plantings.open.where(own_soil: false).update_all(soil) if soil.any?
    plantings.open.update_all(values.slice(:pivot_id, :weather_cell_id)) if values.key?(:pivot_id)
    # Part-field plantings keep their own area (G.11)
    plantings.open.where(partial: false).update_all(area_acres:) if values.key?(:area_acres)
  end

  # Checked when the outline changes, so one saved under older limits doesn't block other edits
  def boundary_readable
    return if boundary.nil? || !will_save_change_to_boundary?
    FieldBoundary.errors(boundary).each { |message| errors.add(:boundary, message) }
  end

  def wilting_point_below_capacity
    return unless soil_type
    unless effective_perm_wilting_pt < effective_field_capacity
      errors.add(:perm_wilting_pt, "must be below field capacity")
    end
  end
end

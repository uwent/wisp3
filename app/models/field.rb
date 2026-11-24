class Field < ApplicationRecord
  belongs_to :system, class_name: "IrrigationSystem"
  belongs_to :soil_type
  has_one :farm, through: :system
  has_many :plantings, -> { order(:season_start, :id) }, dependent: :destroy
  has_many :field_entries, dependent: :destroy
  has_many :digest_exclusions, as: :subject, dependent: :delete_all

  # What the field and planting pages read: the field's system and every planting with its balance's inputs
  scope :with_season_tree, -> {
    includes(:soil_type, system: [:farm, :weather_cell, :irrigation_group],
      plantings: [:plant, :canopy_observations, :canopy_cuttings, :soil_type, :weather_cell])
  }

  validates :name, presence: true, length: {maximum: 100}
  validates :area_acres, numericality: {greater_than: 0}, allow_nil: true
  validates :field_capacity, :perm_wilting_pt, numericality: {greater_than: 0, less_than: 0.6}, allow_nil: true
  validate :wilting_point_below_capacity
  validate :boundary_readable

  normalizes_name :name
  normalizes_text :notes

  # Plantings that haven't ended follow the field's soil, area and system;
  # ended ones keep what their season ran with, so a field can move at any time
  after_update :update_open_plantings

  # The outline: a GeoJSON Polygon with one ring, or nil. A JSON string is parsed and
  # blank clears it; positions are rounded (FieldBoundary.normalize).
  def boundary=(value)
    super(value.blank? ? nil : FieldBoundary.normalize(value))
  end

  # The outline's area in acres, or nil without one. Offered for area_acres, never copied to it.
  def boundary_acres = boundary && FieldBoundary.acres(boundary)

  # NULL means "use the soil type's value" (C14)
  def effective_field_capacity = field_capacity || soil_type.field_capacity
  def effective_perm_wilting_pt = perm_wilting_pt || soil_type.perm_wilting_pt

  # The planting whose season includes date, if any: the whole-field one, else the first part-field
  # one (a field can have several of those at once; plantings_on gives them all)
  def planting_on(date)
    plantings_on(date).min_by(&:order_key)
  end

  # Every planting whose season includes date
  def plantings_on(date)
    plantings.select { |planting| planting.season_range.cover?(date) }
  end

  # Records the field's entry for date (FieldEntry.record, values: any of DailyEntry::VALUES) and,
  # when its irrigation changes, makes the same change on each plot in season that day that had the
  # field's amount (D15: a plot's irrigation is its own, and one that had the field's follows it),
  # but never a rainfed plot, which takes only what's entered for it (D17).
  # plots_sent: plots whose own values the same save sets (daily entry's plot rows), left alone.
  # Returns the field's entry; check its errors.
  def record_entry(date, values, plots_sent: [])
    values = values.to_h.symbolize_keys
    before = field_entries.find_by(date:)&.irrigation_in
    entry = FieldEntry.record(field_entries, date, values)
    return entry if entry.errors.any? || !values.key?(:irrigation_in) || entry.irrigation_in == before

    plantings_on(date).select { |planting| planting.partial? && !planting.rainfed? && plots_sent.exclude?(planting.id) }.each do |plot|
      next unless plot.planting_entries.find_by(date:)&.irrigation_in == before
      PlantingEntry.record(plot.planting_entries, date, irrigation_in: entry.irrigation_in)
    end
    entry
  end

  # The plots an irrigation system's amount goes to that day in place of the field: its irrigated
  # plots, when the field has nothing of its own to water (its whole-field crop is rainfed, D17 and
  # D19, or it's growing only plots), as daily entry and its week fill them; none otherwise
  def system_plots_on(date)
    plantings = plantings_on(date)
    return [] if plantings.any? { |planting| !planting.partial? && !planting.rainfed? }
    plantings.select { |planting| planting.partial? && !planting.rainfed? }.sort_by(&:order_key)
  end

  # Records an irrigation system's amount on the field (its page and the dashboard's log): the
  # field's entry (record_entry, its plots following), or each of system_plots_on's own. Returns an
  # entry; check its errors.
  def record_system_irrigation(date, inches)
    plots = system_plots_on(date)
    return record_entry(date, {irrigation_in: inches}) if plots.empty?
    entries = plots.map { |plot| PlantingEntry.record(plot.planting_entries, date, irrigation_in: inches) }
    entries.find { |entry| entry.errors.any? } || entries.first
  end

  # The irrigation systems' pages and the log show for fields (their plantings loaded) over dates,
  # {[field_id, date] => entry}: the field's entry, or on a day system_plots_on has plots, the first
  # of those with an amount (record_system_irrigation gives them all the same)
  def self.system_irrigation(fields, dates)
    entries = FieldEntry.where(field_id: fields.map(&:id), date: dates).where.not(irrigation_in: nil)
      .index_by { |entry| [entry.field_id, entry.date] }
    plots = fields.flat_map { |field| field.plantings.select { |planting| planting.partial? && !planting.rainfed? } }
    return entries if plots.empty?

    plot_entries = PlantingEntry.where(planting_id: plots.map(&:id), date: dates).where.not(irrigation_in: nil)
      .index_by { |entry| [entry.planting_id, entry.date] }
    by_id = fields.index_by(&:id)
    plot_field = plots.to_h { |plot| [plot.id, plot.field_id] }
    # The days that could change: those with a plot's amount or such a field's own
    days = plot_entries.keys.map { |plot_id, date| [plot_field[plot_id], date] } +
      entries.keys.select { |field_id, _| plot_field.value?(field_id) }
    days.uniq.each do |field_id, date|
      watered = by_id[field_id].system_plots_on(date)
      next if watered.empty?
      entry = watered.lazy.filter_map { |plot| plot_entries[[plot.id, date]] }.first
      entry ? entries[[field_id, date]] = entry : entries.delete([field_id, date])
    end
    entries
  end

  # The irrigation system the field was on that day: its planting's (a season keeps the system it
  # ran on), else, with nothing planted, the one it's on now
  def system_id_on(date) = planting_on(date)&.system_id || system_id

  # Saves the field, moved to system if given: one of its operation's, or a new Location
  # (unsaved), added in the same transaction. Its open plantings follow (update_open_plantings);
  # ended ones keep the system they ran on. False with errors on the field when either can't be saved.
  def save_moving_to(system)
    saved = Field.transaction do
      if system&.new_record? && !system.save
        errors.add(:system_id, "couldn't be added as a Location: #{system.errors.full_messages.to_sentence}")
        raise ActiveRecord::Rollback
      end
      self.system = system if system
      save || raise(ActiveRecord::Rollback)
    end
    saved || false
  end

  private

  def update_open_plantings
    changed = Planting::FIELD_VALUES.select { |attribute| saved_change_to_attribute?(attribute) }
    values = changed.to_h { |attribute| [attribute, self[attribute]] }
    if saved_change_to_system_id?
      values[:system_id] = system_id
      values[:weather_cell_id] = system.weather_cell_id
    end
    # Plots on their own soil keep it. The soil type and its two overrides go together, so a
    # planting whose soil was corrected for its season never ends up with part of each
    soil = slice(:soil_type_id, :field_capacity, :perm_wilting_pt)
    plantings.open.where(own_soil: false).update_all(soil) if values.keys.intersect?(soil.keys.map(&:to_sym))
    plantings.open.update_all(values.slice(:system_id, :weather_cell_id)) if values.key?(:system_id)
    # Part-field plantings keep their own area
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

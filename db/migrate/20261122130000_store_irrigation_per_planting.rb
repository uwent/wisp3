# D15 (2026-11-22): irrigation is stored per field and per plot, in inches, never inherited
# from the irrigation system. Each planting keeps the irrigation the old precedence gave it
# (DailyInputs before D15):
#
#   a plot:  its own entry ?? its field's own entry ?? the irrigation of the plot's system (if it
#            covered the field) — so first plots take their field's own amount, then their system's;
#   a field: its own entry ?? its system's that day (fields_on), with that irrigation's notes where
#            the field's entry has none.
#
# Run hours convert as PivotIrrigation#applied_inches did. A row that can't be converted (no pump
# capacity or a field's area missing) or that no field or plot is under any more is reported (say),
# and its run hours kept in the notes of the fields' entries it covered. pivot_irrigations is
# dropped; going down recreates it empty.
class StoreIrrigationPerPlanting < ActiveRecord::Migration[8.1]
  GALLONS_PER_ACRE_INCH = 27_154

  class Irrigation < ActiveRecord::Base
    self.table_name = "pivot_irrigations"
  end

  class System < ActiveRecord::Base
    self.table_name = "pivots"
  end

  class Land < ActiveRecord::Base
    self.table_name = "fields"
  end

  class Crop < ActiveRecord::Base
    self.table_name = "plantings"
    self.inheritance_column = nil
    scope :on, ->(date) { where("season_start <= ? AND end_date >= ?", date, date) }
    def order_key = [partial ? 1 : 0, season_start, id]
  end

  class Entry < ActiveRecord::Base
    self.table_name = "field_entries"
  end

  class PlotEntry < ActiveRecord::Base
    self.table_name = "planting_entries"
  end

  def up
    # A plot's own entry, else its field's own (before the systems' irrigation is spread onto fields)
    execute <<~SQL
      INSERT INTO planting_entries (planting_id, date, irrigation_in, created_at, updated_at)
      SELECT plantings.id, field_entries.date, field_entries.irrigation_in, now(), now()
      FROM plantings JOIN field_entries ON field_entries.field_id = plantings.field_id
      WHERE plantings.partial AND field_entries.irrigation_in IS NOT NULL
        AND field_entries.date BETWEEN plantings.season_start AND plantings.end_date
      ON CONFLICT (planting_id, date) DO UPDATE SET irrigation_in = EXCLUDED.irrigation_in, updated_at = now()
        WHERE planting_entries.irrigation_in IS NULL
    SQL

    Irrigation.order(:id).find_each { |irrigation| spread(irrigation) }

    drop_table :pivot_irrigations
  end

  def down
    create_table :pivot_irrigations do |t|
      t.references :pivot, null: false, foreign_key: true, index: false
      t.date :date, null: false
      t.float :inches
      t.float :run_hours
      t.bigint :field_ids, array: true
      t.text :notes
      t.timestamps
      t.index [:pivot_id, :date], unique: true
      t.check_constraint "inches IS NULL OR inches >= 0", name: "pivot_irrigations_inches_nonnegative"
      t.check_constraint "run_hours IS NULL OR run_hours >= 0", name: "pivot_irrigations_run_hours_nonnegative"
      t.check_constraint "num_nonnulls(inches, run_hours) >= 1", name: "pivot_irrigations_amount"
    end
  end

  private

  def spread(irrigation)
    date = irrigation.date
    covers = ->(field_id) { irrigation.field_ids.nil? || irrigation.field_ids.include?(field_id) }
    fields = fields_on(irrigation.pivot_id, date).select { |field| covers.call(field.id) }
    plots = Crop.on(date).where(pivot_id: irrigation.pivot_id, partial: true).select { |plot| covers.call(plot.field_id) }
    inches = irrigation.inches || from_run_hours(irrigation, fields, plots)

    if inches.nil? || (fields.empty? && plots.empty?)
      say "pivot_irrigation #{irrigation.id} (pivot #{irrigation.pivot_id}, #{date}, inches #{irrigation.inches.inspect}, " \
        "run hours #{irrigation.run_hours.inspect}, notes #{irrigation.notes.inspect}): " \
        "#{inches.nil? ? "run hours can't be converted" : "no field or plot under it"}; not moved"
      note_unconverted(irrigation, fields) if inches.nil?
      return
    end

    plots.each do |plot|
      entry = PlotEntry.find_or_initialize_by(planting_id: plot.id, date:)
      next unless entry.irrigation_in.nil?
      entry.update!(irrigation_in: inches.round(4))
    end
    fields.each do |field|
      entry = Entry.find_or_initialize_by(field_id: field.id, date:)
      entry.irrigation_in = inches.round(4) if entry.irrigation_in.nil?
      entry.notes = irrigation.notes if entry.notes.blank? && irrigation.notes.present?
      entry.save! if entry.changed?
    end
  end

  # Run hours that couldn't be converted stay readable in the fields' notes
  def note_unconverted(irrigation, fields)
    text = ["Ran #{format("%g", irrigation.run_hours)} h (not converted to inches)", irrigation.notes.presence].compact.join("; ")
    fields.each do |field|
      entry = Entry.find_or_initialize_by(field_id: field.id, date: irrigation.date)
      entry.notes = [entry.notes.presence, text].compact.join("; ")
      entry.save!
    end
  end

  # Pivot#fields_on: fields whose planting that day ran on the system, and its own with nothing planted
  def fields_on(pivot_id, date)
    candidates = Land.where(pivot_id:).or(Land.where(id: Crop.on(date).where(pivot_id:).select(:field_id)))
    candidates.select do |field|
      planting = Crop.on(date).where(field_id: field.id).min_by(&:order_key)
      (planting&.pivot_id || field.pivot_id) == pivot_id
    end
  end

  # PivotIrrigation#applied_inches from run hours: gpm × minutes over the acres watered that day, the
  # covered fields with a planting in season on the system (each at its whole-field planting's
  # area, else the field's), else the system's covered fields
  def from_run_hours(irrigation, fields, plots)
    gpm = System.find(irrigation.pivot_id).pump_capacity_gpm
    return if gpm.nil? || irrigation.run_hours.nil?
    covered = ->(field_id) { irrigation.field_ids.nil? || irrigation.field_ids.include?(field_id) }
    in_season = Crop.on(irrigation.date).where(pivot_id: irrigation.pivot_id).select { |planting| covered.call(planting.field_id) }
    areas = if in_season.empty?
      Land.where(pivot_id: irrigation.pivot_id).select { |field| covered.call(field.id) }.map(&:area_acres)
    else
      in_season.group_by(&:field_id).map do |field_id, plantings|
        plantings.find { |planting| !planting.partial }&.area_acres || Land.find(field_id).area_acres
      end
    end
    return if areas.empty? || areas.any?(&:nil?)
    gpm * irrigation.run_hours * 60 / (GALLONS_PER_ACRE_INCH * areas.sum)
  end
end

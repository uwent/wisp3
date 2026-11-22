# Saves what daily entry submits for one date (PLAN.md Phase 8 G.4), for the day page and for each
# day of the week view (Phase 9 §6): each field's entry, each part-field planting's own entry and
# each planting's canopy reading, checked in the models' :entry validation context. Irrigation is
# stored per field and plot (D15): a field's saved here also sets its plots that had the field's
# amount, unless the same save sends the plot's own (the day page's plot rows). Only the values sent
# change: a field sent with only its rain keeps its irrigation and soil moisture (FieldEntry.record
# assigns what it's given). Records are found through the group, so another group's ids are
# ignored. Errors go into the hash given, keyed "#{prefix}fields.<id>.<attribute>" and so on; the
# caller runs it in a transaction and rolls back when there are any.
class DailyEntrySave
  def initialize(group, date, prefix: "")
    @group, @date, @prefix = group, date, prefix
  end

  # values: the date's parameters (fields, plantings, canopy; any may be missing)
  def record(values, errors)
    return unless values.is_a?(ActionController::Parameters)
    plantings = by_id(values[:plantings], %i[irrigation_in soil_moisture_pct])
    # Plots whose own irrigation this save sets don't follow their field's
    plots_sent = plantings.select { |_, values| values.key?("irrigation_in") }.keys.map(&:to_i)
    record_fields(by_id(values[:fields], DailyEntry::VALUES), plots_sent, errors)
    record_plantings(plantings, errors)
    record_canopy(values[:canopy], errors)
  end

  private

  # {"id" => {attribute => value}} for the records sent, with only these attributes; an id sent
  # without a hash of values is dropped
  def by_id(values, attributes)
    return {} unless values.is_a?(ActionController::Parameters)
    values.permit(values.keys.index_with { attributes }).to_h
  end

  def add_errors(errors, key, record)
    record.errors.to_hash(true).each { |attribute, messages| errors["#{@prefix}#{key}.#{attribute}"] = messages }
  end

  def record_fields(values, plots_sent, errors)
    @group.fields.where(id: values.keys).includes(:plantings).find_each do |field|
      entry = field.record_entry(@date, values[field.id.to_s], plots_sent:)
      add_errors(errors, "fields.#{field.id}", entry)
    end
  end

  # A part-field planting's own irrigation and soil moisture (a whole-field planting's are the field's)
  def record_plantings(values, errors)
    @group.plantings.where(id: values.keys, partial: true).find_each do |planting|
      entry = PlantingEntry.record(planting.planting_entries, @date, values[planting.id.to_s])
      add_errors(errors, "plantings.#{planting.id}", entry)
    end
  end

  # {planting_id => value}: percent cover or LAI by the planting's ET method; blank removes the reading
  def record_canopy(values, errors)
    return unless values.is_a?(ActionController::Parameters)
    values = values.permit(*values.keys).to_h
    @group.plantings.where(id: values.keys).find_each do |planting|
      observation = CanopyObservation.record(planting, @date, values[planting.id.to_s])
      errors["#{@prefix}canopy.#{planting.id}"] = observation.errors.full_messages if observation.errors.any?
    end
  end
end

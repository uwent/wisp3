# Saves what daily entry submits for one date (PLAN.md Phase 8 G.4), for the day page and for each
# day of the week view (Phase 9 §6): each system's irrigation, each field's entry, each part-field
# planting's own entry and each planting's canopy reading, checked in the models' :entry validation
# context. Only the values sent change: a field sent with only its rain keeps its irrigation and soil
# moisture (FieldEntry.record assigns what it's given). Records are found through the group, so
# another group's ids are ignored. Errors go into the hash given, keyed
# "#{prefix}pivots.<id>.<attribute>" and so on; the caller runs it in a transaction and rolls back
# when there are any.
class DailyEntrySave
  def initialize(group, date, prefix: "")
    @group, @date, @prefix = group, date, prefix
  end

  # values: the date's parameters (pivots, fields, plantings, canopy; any may be missing)
  def record(values, errors)
    return unless values.is_a?(ActionController::Parameters)
    record_pivots(by_id(values[:pivots], [:inches, :run_hours, :notes, field_ids: []]), errors)
    record_fields(by_id(values[:fields], DailyEntry::VALUES), errors)
    record_plantings(by_id(values[:plantings], %i[irrigation_in soil_moisture_pct]), errors)
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

  # A system sent with neither inches nor run hours has its irrigation for the day removed
  def record_pivots(values, errors)
    @group.pivots.where(id: values.keys).find_each do |pivot|
      submitted = values[pivot.id.to_s]
      irrigation = pivot.pivot_irrigations.find_or_initialize_by(date: @date)
      if submitted["inches"].blank? && submitted["run_hours"].blank?
        irrigation.destroy! if irrigation.persisted?
        next
      end
      submitted["field_ids"] = PivotIrrigation.normalize_field_ids(pivot, submitted["field_ids"], @date)
      next if irrigation.update(submitted)
      add_errors(errors, "pivots.#{pivot.id}", irrigation)
    end
  end

  def record_fields(values, errors)
    @group.fields.where(id: values.keys).find_each do |field|
      entry = FieldEntry.record(field.field_entries, @date, values[field.id.to_s])
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

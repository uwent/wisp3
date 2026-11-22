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
    record_pivots(by_id(values[:pivots], [*PivotIrrigation::AMOUNTS, :notes, field_ids: []]), errors)
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

  # A system sent with no amount (inches, run hours or percent) has its irrigation for the day removed
  def record_pivots(values, errors)
    @group.pivots.where(id: values.keys).find_each do |pivot|
      submitted = values[pivot.id.to_s]
      irrigation = pivot.pivot_irrigations.find_or_initialize_by(date: @date)
      if submitted.values_at("inches", "run_hours", "percent_timer").all?(&:blank?)
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
      submitted = values[field.id.to_s]
      next if percent_irrigation(field, submitted, errors)
      entry = FieldEntry.record(field.field_entries, @date, submitted)
      add_errors(errors, "fields.#{field.id}", entry)
    end
  end

  # A field's irrigation entered as the percent timer's setting (docs/plans/phase-9.md §8) is saved as
  # the inches it puts on that day under the field's system, with the percent kept to show it as
  # entered. Adds an error and returns true when the system has no depth at 100%.
  def percent_irrigation(field, submitted, errors)
    percent = submitted["irrigation_pct"].presence&.to_f
    return false unless percent
    pivot = @group.pivots.find_by(id: field.pivot_id_on(@date))
    inches = pivot&.inches_at_percent(percent) if percent.positive? && percent <= 100
    if inches
      submitted["irrigation_in"] = inches.round(4)
      return false
    end
    message = pivot&.percent_timer? ? "must be more than 0 and at most 100" : "needs the system's depth at 100%; enter inches instead"
    errors["#{@prefix}fields.#{field.id}.irrigation_pct"] = [message]
    true
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

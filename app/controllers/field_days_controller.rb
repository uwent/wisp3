# Saves one day of a field's grid: the field entry (rain, irrigation, soil moisture, notes) and,
# with planting_id, that planting's canopy reading (percent cover or LAI, by its ET method). For a
# planting on part of the field (PLAN.md Phase 8 G.11), its irrigation, soil moisture and notes go
# to its own entry (PlantingEntry) and rain to the field's. Only the values sent change; a blank
# value clears it. A future day takes only planned irrigation and notes: rain and readings haven't
# happened yet.
class FieldDaysController < AuthenticatedController
  FUTURE_VALUES = %i[irrigation_in notes].freeze

  def update
    field = Current.group.fields.find(params[:field_id])
    date = Date.iso8601(params[:date])
    values = params.expect(day: [*DailyEntry::VALUES, :canopy])

    if date > Date.current
      future = values.to_h.symbolize_keys.except(*FUTURE_VALUES).select { |_, value| value.present? }
      if future.any?
        return redirect_with_errors(request.referer || field_path(field),
          future.keys.to_h { |key| [key, ["can't be entered for a future date; only planned irrigation and notes can"]] })
      end
    end

    part = field.plantings.find(params[:planting_id]) if params[:planting_id].present?
    part = nil unless part&.partial?
    entry_values = values.except(:canopy).to_h.symbolize_keys
    errors = {}
    FieldEntry.transaction do
      if part
        own = entry_values.slice(*PlantingEntry.entry_values)
        if own.any?
          errors.merge!(PlantingEntry.record(part.planting_entries, date, own).errors.to_hash(true))
        end
        entry_values = entry_values.except(*PlantingEntry.entry_values)
      end
      if entry_values.any?
        errors.merge!(FieldEntry.record(field.field_entries, date, entry_values).errors.to_hash(true))
      end
      errors.merge!(record_canopy(field, date, values[:canopy])) if values.key?(:canopy)
      raise ActiveRecord::Rollback if errors.any?
    end

    target = request.referer || field_path(field)
    errors.any? ? redirect_with_errors(target, errors) : redirect_to(target)
  rescue Date::Error
    raise ActionController::BadRequest, "Invalid date"
  end

  private

  # {} or {canopy: [messages]}
  def record_canopy(field, date, value)
    planting = field.plantings.find(params.expect(:planting_id))
    return {canopy: ["is outside this planting's season"]} unless planting.season_range.cover?(date)

    observation = CanopyObservation.record(planting, date, value)
    observation.errors.any? ? {canopy: observation.errors.full_messages} : {}
  end
end

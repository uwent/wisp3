# Saves one day of a field's grid: the field entry (rain, irrigation, soil moisture, notes) and,
# with planting_id, that planting's canopy reading (percent cover or LAI, by its ET method). For a
# planting on part of the field, its irrigation, soil moisture and notes go
# to its own entry (PlantingEntry) and rain to the field's; the field's irrigation also sets its plots
# that had the field's amount (Field#record_entry, D15). Only the values sent change; a blank
# value clears it. A future day takes only planned irrigation and notes (DailyEntry and
# CanopyObservation check: rain and readings haven't happened yet).
class FieldDaysController < AuthenticatedController
  def update
    field = Current.group.fields.find(params[:field_id])
    date = parse_date(params[:date]) or raise ActionController::BadRequest, "Invalid date"
    values = params.expect(day: [*DailyEntry::VALUES, :canopy])

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
        errors.merge!(field.record_entry(date, entry_values).errors.to_hash(true))
      end
      errors.merge!(record_canopy(field, date, values[:canopy])) if values.key?(:canopy)
      raise ActiveRecord::Rollback if errors.any?
    end

    target = request.referer || field_path(field)
    errors.any? ? redirect_with_errors(target, errors) : redirect_to(target)
  end

  private

  # {} or {canopy: [messages]}
  def record_canopy(field, date, value)
    planting = field.plantings.find(params.expect(:planting_id))
    observation = CanopyObservation.record(planting, date, value)
    observation.errors.any? ? {canopy: observation.errors.full_messages} : {}
  end
end

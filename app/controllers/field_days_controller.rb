# Saves one day of a field's grid: the field entry (rain, irrigation, soil moisture, notes) and,
# with planting_id, that planting's canopy reading (percent cover or LAI, by its ET method). Only
# the values sent change; a blank value clears it.
class FieldDaysController < AuthenticatedController
  def update
    field = Current.group.fields.find(params[:field_id])
    date = Date.iso8601(params[:date])
    values = params.expect(day: [*DailyEntry::VALUES, :canopy])

    errors = {}
    FieldEntry.transaction do
      entry = FieldEntry.record(field.field_entries, date, values.except(:canopy))
      errors.merge!(entry.errors.to_hash(true))
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

    attribute = (planting.et_method == "lai") ? :lai : :pct_cover
    observation = planting.canopy_observations.find_or_initialize_by(date:)
    if value.blank?
      observation.destroy! if observation.persisted?
      return {}
    end
    observation.assign_attributes(pct_cover: nil, lai: nil)
    observation[attribute] = value
    observation.save ? {} : {canopy: observation.errors.full_messages}
  end
end

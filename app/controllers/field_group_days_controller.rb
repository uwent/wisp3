# Saves one day of a field group's entries; a blank value clears it. Percent cover isn't a group
# entry: it becomes a canopy reading on each member field's percent-cover crop that day (PLAN.md §4).
class FieldGroupDaysController < AuthenticatedController
  def update
    group = Current.group.field_groups.find(params[:field_group_id])
    date = Date.iso8601(params[:date])
    values = params.expect(day: [*DailyEntry::VALUES, :pct_cover])

    errors = {}
    FieldGroupEntry.transaction do
      if values.except(:pct_cover).present?
        entry = FieldGroupEntry.record(group.field_group_entries, date, values.except(:pct_cover))
        errors.merge!(entry.errors.to_hash(true))
      end
      errors.merge!(record_cover(group, date, values[:pct_cover])) if values.key?(:pct_cover)
      raise ActiveRecord::Rollback if errors.any?
    end

    target = request.referer || field_group_path(group)
    errors.any? ? redirect_with_errors(target, errors) : redirect_to(target)
  rescue Date::Error
    raise ActionController::BadRequest, "Invalid date"
  end

  private

  # {} or {pct_cover: [messages]}
  def record_cover(group, date, value)
    plantings = group.fields.includes(:plantings).filter_map { |field| field.planting_on(date) }
      .select { |planting| planting.et_method == "pct_cover" }
    return {pct_cover: ["can't be entered: no field in this group has a percent-cover crop on this date"]} if plantings.empty?

    messages = plantings.flat_map { |planting| CanopyObservation.record(planting, date, value).errors.full_messages }
    messages.any? ? {pct_cover: messages.uniq} : {}
  end
end

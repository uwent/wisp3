# Saves one day of a field group's entries; a blank value clears it
class FieldGroupDaysController < AuthenticatedController
  def update
    group = Current.group.field_groups.find(params[:field_group_id])
    date = Date.iso8601(params[:date])
    entry = FieldGroupEntry.record(group.field_group_entries, date, params.expect(day: [*DailyEntry::VALUES]))

    target = request.referer || field_group_path(group)
    entry.errors.any? ? redirect_with_errors(target, entry) : redirect_to(target)
  rescue Date::Error
    raise ActionController::BadRequest, "Invalid date"
  end
end

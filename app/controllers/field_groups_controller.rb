# Field groups share data entry (e.g. one rain gauge for several fields). Their entries apply to
# member fields when read, below the fields' own entries and pivot irrigation (DailyInputs).
class FieldGroupsController < AuthenticatedController
  def index
    render inertia: "FieldGroups/Index", props: {
      field_groups: FieldGroupSerializer.new(Current.group.field_groups.includes(:fields).order(:name)).to_h,
      fields: field_choices
    }
  end

  # The group's entries for a season, one row per day from April 1 through today (or the season's end)
  def show
    group = Current.group.field_groups.find(params[:id])
    year = params.fetch(:year, Date.current.year).to_i
    plantings = Planting.where(field_id: group.field_ids).in_season(year)
    from = [plantings.minimum(:season_start), Date.new(year, 4, 1)].compact.min
    to = [[plantings.maximum(:end_date), Date.new(year, 11, 30)].compact.max, Date.current].min
    entries = group.field_group_entries.where(date: from..to).index_by(&:date)

    render inertia: "FieldGroups/Show", props: {
      field_group: FieldGroupSerializer.new(group).to_h,
      fields: field_choices,
      year:,
      days: (from..to).map do |date|
        entry = entries[date]
        {date:, rain_in: entry&.rain_in, irrigation_in: entry&.irrigation_in,
         soil_moisture_pct: entry&.soil_moisture_pct, notes: entry&.notes}
      end
    }
  end

  def create
    group = Current.group.field_groups.build(name: group_params[:name])
    group.fields = member_fields
    if group.save
      redirect_to field_group_path(group), notice: "Created #{group.name}"
    else
      redirect_with_errors field_groups_path, group
    end
  end

  def update
    group = Current.group.field_groups.find(params[:id])
    group.assign_attributes(group_params.slice(:name))
    group.fields = member_fields if group_params.key?(:field_ids)
    if group.save
      redirect_back_or_to field_group_path(group), notice: "Saved #{group.name}"
    else
      redirect_with_errors(request.referer || field_groups_path, group)
    end
  end

  def destroy
    group = Current.group.field_groups.find(params[:id])
    group.destroy!
    redirect_to field_groups_path, notice: "Deleted #{group.name}"
  end

  private

  def group_params = params.expect(field_group: [:name, field_ids: []])

  # Only the group's own fields can be members
  def member_fields = Current.group.fields.where(id: group_params.fetch(:field_ids, []).compact_blank)

  def field_choices
    Current.group.fields.includes(pivot: :farm).map do |field|
      {id: field.id, name: field.name, pivot_name: field.pivot.name, farm_name: field.pivot.farm.name}
    end
  end
end

# The props of daily entry's week view (Phase 9 §6): rain and irrigation for the seven days ending on
# a date, for a grower entering several days at once. Per farm, rain rows (each irrigation group with
# a system in season any day of the week, then each system in season in no group, as the day page
# orders them: farmRows in lib/dailyEntry.ts) and irrigation rows (each system in season any day).
# Per row and day: whether it takes a value (a field in season under it that day; Field#pivot_id_on
# places a field under the system its season ran on), for rain the fields it fills with their
# amounts and their common value or "varies", for irrigation that day's PivotIrrigation and whether
# it applies to only some fields. Fields, plots and canopy readings stay on the day page. Loads
# everything in a few queries, with none per field or day.
class DailyEntryWeek
  DAYS = 7

  attr_reader :dates

  def initialize(group, date)
    @group = group
    @dates = ((date - (DAYS - 1))..date).to_a
  end

  def farms
    @farms ||= @group.farms.order(:name).includes(:pivot_groups, pivots: [:weather_cell, {fields: :plantings}]).to_a
  end

  def pivots = farms.flat_map(&:pivots)

  def props
    {date: dates.last, start: dates.first, dates:, has_systems: pivots.any?, farms: farms.filter_map { |farm| farm_props(farm) }}
  end

  private

  def farm_props(farm)
    active = farm.pivots.select { |pivot| dates.any? { |date| growing(pivot, date).any? } }
    return if active.empty?

    groups = farm.pivot_groups.filter_map do |pivot_group|
      systems = active.select { |pivot| pivot.pivot_group_id == pivot_group.id }
      [pivot_group, systems] if systems.any?
    end
    ungrouped = active.reject { |pivot| groups.any? { |_, systems| systems.include?(pivot) } }

    rain_rows = groups.map { |pivot_group, systems|
      rain_row("group-#{pivot_group.id}", pivot_group.name, systems).merge(kind: "group", systems: systems.size)
    } + ungrouped.map { |pivot|
      rain_row("pivot-#{pivot.id}", pivot.name, [pivot]).merge(kind: "system", kind_name: pivot.kind_name)
    }
    {id: farm.id, name: farm.name, rain_rows:,
     irrigation_rows: (groups.flat_map(&:last) + ungrouped).map { |pivot| irrigation_row(pivot) }}
  end

  def rain_row(key, name, systems)
    {key:, name:, days: dates.map { |date| rain_day(systems.flat_map { |pivot| growing(pivot, date) }, date) }}
  end

  def rain_day(fields, date)
    amounts = fields.sort_by(&:name).map do |field|
      {id: field.id, name: field.name, rain_in: field_entries[[field.id, date]]&.rain_in}
    end
    values = amounts.map { |amount| amount[:rain_in] }.uniq
    {active: fields.any?, value: (values.first if values.one?), varies: values.size > 1, fields: amounts}
  end

  def irrigation_row(pivot)
    {id: pivot.id, name: pivot.name, kind: pivot.kind, kind_name: pivot.kind_name,
     # Run hours convert through the pump capacity and the fields' areas (canUseHours in lib/irrigation.ts)
     hours: pivot.pump_capacity_gpm.present? && pivot.fields.all?(&:area_acres),
     days: dates.map { |date| irrigation_day(pivot, date) }}
  end

  def irrigation_day(pivot, date)
    irrigation = irrigations[[pivot.id, date]]
    under = on_system(pivot, date)
    left_out = irrigation&.field_ids ? under.reject { |field| irrigation.field_ids.include?(field.id) } : []
    applied = under.select { |field| irrigation&.covers?(field.id) }
    {active: growing(pivot, date).any? || irrigation.present?,
     irrigation: irrigation&.slice(:inches, :run_hours, :field_ids),
     # Applied to only some of the fields on the system that day: their names
     some_fields: (applied.map(&:name) if left_out.any?)}
  end

  # The fields under the system on the date (its own, or those whose season there ran on it), by name
  def on_system(pivot, date)
    @on_system ||= dates.index_with do |day|
      fields.group_by { |field| field.pivot_id_on(day) }.transform_values { |list| list.sort_by(&:name) }
    end
    @on_system[date].fetch(pivot.id, [])
  end

  # Those with something growing that day
  def growing(pivot, date) = on_system(pivot, date).select { |field| field.plantings_on(date).any? }

  def fields = @fields ||= pivots.flat_map(&:fields)

  def irrigations
    @irrigations ||= PivotIrrigation.where(pivot: pivots, date: dates.first..dates.last).index_by { |irrigation| [irrigation.pivot_id, irrigation.date] }
  end

  def field_entries
    @field_entries ||= FieldEntry.where(field_id: fields.map(&:id), date: dates.first..dates.last)
      .index_by { |entry| [entry.field_id, entry.date] }
  end
end

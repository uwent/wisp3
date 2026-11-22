# The props of daily entry's week view (Phase 9 §6): rain and irrigation for the seven days ending on
# a date, for a grower entering several days at once. Per farm, rain rows (each irrigation group with
# a system in season any day of the week, then each system in season in no group, as the day page
# orders them: farmRows in lib/dailyEntry.ts) and irrigation rows (each system in season any day).
# Per row and day: whether it takes a value (a field in season under it that day; Field#pivot_id_on
# places a field under the system its season ran on), and the fields typing there fills with their
# amounts and their common value or "varies": rain for a group's or system's fields, irrigation for
# a system's (stored per field, D15; saving a field's also sets its plots that had its amount).
# Fields, plots and canopy readings stay on the day page. Loads everything in a few queries, with
# none per field or day.
class DailyEntryWeek
  DAYS = 7

  attr_reader :dates

  def initialize(group, date)
    @group = group
    @dates = ((date - (DAYS - 1))..date).to_a
  end

  def farms
    @farms ||= @group.farms.order(:name).includes(:pivot_groups, pivots: [:weather_cell, {fields: {plantings: :plant}}]).to_a
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
      row("group-#{pivot_group.id}", pivot_group.name, systems, :rain_in).merge(kind: "group", systems: systems.size)
    } + ungrouped.map { |pivot|
      row("pivot-#{pivot.id}", pivot.name, [pivot], :rain_in).merge(kind: "system", kind_name: pivot.kind_name)
    }
    {id: farm.id, name: farm.name, rain_rows:,
     irrigation_rows: (groups.flat_map(&:last) + ungrouped).map do |pivot|
       row("pivot-#{pivot.id}", pivot.name, [pivot], :irrigation_in).merge(id: pivot.id, kind: pivot.kind, kind_name: pivot.kind_name,
         # For the irrigation calculator (IrrigationCalculator)
         pump_capacity_gpm: pivot.pump_capacity_gpm, inches_at_100: pivot.inches_at_100)
     end}
  end

  # attribute: :rain_in or :irrigation_in; irrigation's fields carry the acres the calculator spreads
  # run hours over (the whole-field planting's area that day, else the field's). For irrigation, a
  # field growing only plots that day is its plots (it has nothing of its own to water, as on the day
  # page), each saved as the plot's own (plot: true)
  def row(key, name, systems, attribute)
    {key:, name:, days: dates.map { |date| day(systems.flat_map { |pivot| growing(pivot, date) }, date, attribute) }}
  end

  def day(fields, date, attribute)
    amounts = fields.sort_by(&:name).flat_map do |field|
      value = field_entries[[field.id, date]]&.public_send(attribute)
      next [{id: field.id, name: field.name, value:}] unless attribute == :irrigation_in
      plantings = field.plantings_on(date)
      whole = plantings.find { |planting| !planting.partial? }
      next [{id: field.id, name: field.name, value:, acres: whole&.area_acres || field.area_acres}] if whole || plantings.empty?
      plantings.sort_by(&:order_key).map do |plot|
        {id: plot.id, name: "#{field.name}: #{plot.plant.name}", value: planting_entries[[plot.id, date]]&.irrigation_in,
         acres: plot.area_acres, plot: true}
      end
    end
    values = amounts.map { |amount| amount[:value] }.uniq
    {active: fields.any?, value: (values.first if values.size == 1), varies: values.size > 1, fields: amounts}
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

  def planting_entries
    @planting_entries ||= PlantingEntry.where(planting_id: fields.flat_map(&:plantings).map(&:id), date: dates.first..dates.last)
      .index_by { |entry| [entry.planting_id, entry.date] }
  end

  def field_entries
    @field_entries ||= FieldEntry.where(field_id: fields.map(&:id), date: dates.first..dates.last)
      .index_by { |entry| [entry.field_id, entry.date] }
  end
end

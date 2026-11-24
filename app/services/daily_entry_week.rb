# The props of daily entry's week view: rain and irrigation for the seven days ending on
# a date, for a grower entering several days at once. Per farm, rain rows (each irrigation group with
# a system in season any day of the week, then each system in season in no group, as the day page
# orders them: farmRows in lib/dailyEntry.ts) and irrigation rows (each system with an irrigated
# field in season any day).
# Per row and day: whether it takes a value (a field in season under it that day; Field#system_id_on
# places a field under the system its season ran on), and the fields typing there fills with their
# amounts and their common value or "varies": rain for a group's or system's fields, irrigation for
# a system's (stored per field, D15; saving a field's also sets its plots that had its amount), never
# a rainfed field or plot's (D17: entered on the day page, field by field).
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
    @farms ||= @group.farms.order(:name).includes(:irrigation_groups, systems: [:weather_cell, {fields: {plantings: :plant}}]).to_a
  end

  def systems = farms.flat_map(&:systems)

  def props
    {date: dates.last, start: dates.first, dates:, has_systems: systems.any?, farms: farms.filter_map { |farm| farm_props(farm) }}
  end

  private

  def farm_props(farm)
    active = farm.systems.select { |system| dates.any? { |date| growing(system, date).any? } }
    return if active.empty?

    groups = farm.irrigation_groups.filter_map do |irrigation_group|
      systems = active.select { |system| system.irrigation_group_id == irrigation_group.id }
      [irrigation_group, systems] if systems.any?
    end
    ungrouped = active.reject { |system| groups.any? { |_, systems| systems.include?(system) } }

    rain_rows = groups.map { |irrigation_group, systems|
      row("group-#{irrigation_group.id}", irrigation_group.name, systems, :rain_in).merge(kind: "group", systems: systems.size)
    } + ungrouped.map { |system|
      row("system-#{system.id}", system.name, [system], :rain_in).merge(kind: "system", kind_name: system.kind_name)
    }
    {id: farm.id, name: farm.name, rain_rows:,
     irrigation_rows: (groups.flat_map(&:last) + ungrouped).map do |system|
       row("system-#{system.id}", system.name, [system], :irrigation_in).merge(id: system.id, kind: system.kind, kind_name: system.kind_name,
         # For the irrigation calculator (IrrigationCalculatorDialog)
         pump_capacity_gpm: system.pump_capacity_gpm, inches_at_100: system.inches_at_100)
     end.select { |row| row[:days].any? { |day| day[:active] } }}
  end

  # attribute: :rain_in or :irrigation_in; irrigation's fields carry the acres the calculator spreads
  # run hours over (the whole-field planting's area that day, else the field's). For irrigation, a
  # field growing only plots that day, or a rainfed crop with plots, is its irrigated plots (it has
  # nothing of its own to water, as on the day page), each saved as the plot's own (plot: true)
  def row(key, name, systems, attribute)
    {key:, name:, days: dates.map { |date| day(systems.flat_map { |system| growing(system, date) }, date, attribute) }}
  end

  def day(fields, date, attribute)
    amounts = fields.sort_by(&:name).flat_map do |field|
      value = field_entries[[field.id, date]]&.public_send(attribute)
      next [{id: field.id, name: field.name, value:}] unless attribute == :irrigation_in
      plantings = field.plantings_on(date)
      whole = plantings.find { |planting| !planting.partial? }
      next [{id: field.id, name: field.name, value:, acres: whole&.area_acres || field.area_acres}] if (whole && !whole.rainfed?) || plantings.empty?
      plantings.reject(&:rainfed?).sort_by(&:order_key).map do |plot|
        {id: plot.id, name: "#{field.name}: #{plot.plant.name}", value: planting_entries[[plot.id, date]]&.irrigation_in,
         acres: plot.area_acres, plot: true}
      end
    end
    values = amounts.map { |amount| amount[:value] }.uniq
    active = (attribute == :irrigation_in) ? amounts.any? : fields.any?
    {active:, value: (values.first if values.size == 1), varies: values.size > 1, fields: amounts}
  end

  # The fields under the system on the date (its own, or those whose season there ran on it), by name
  def on_system(system, date)
    @on_system ||= dates.index_with do |day|
      fields.group_by { |field| field.system_id_on(day) }.transform_values { |list| list.sort_by(&:name) }
    end
    @on_system[date].fetch(system.id, [])
  end

  # Those with something growing that day
  def growing(system, date) = on_system(system, date).select { |field| field.plantings_on(date).any? }

  def fields = @fields ||= systems.flat_map(&:fields)

  def planting_entries
    @planting_entries ||= PlantingEntry.where(planting_id: fields.flat_map(&:plantings).map(&:id), date: dates.first..dates.last)
      .index_by { |entry| [entry.planting_id, entry.date] }
  end

  def field_entries
    @field_entries ||= FieldEntry.where(field_id: fields.map(&:id), date: dates.first..dates.last)
      .index_by { |entry| [entry.field_id, entry.date] }
  end
end

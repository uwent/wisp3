# The props of daily entry for one operation on one date: its farms, each
# with its irrigation groups and systems ("systems" in code), each system's fields; each field's
# entry, the rain the model would use, and its plantings in season that day, with a part-field
# planting's own entry and each planting's canopy reading (when one is wanted: PlantingTasks.canopy).
# Irrigation is each field's and plot's own (D15); a system with none that day but some the day
# before gets the day before's amounts, for "Same as yesterday".
# Each field is under the system it was on that day (Field#system_id_on: a season keeps the system
# it ran on), which for today is its own. Loads everything up front, with no query per
# field.
class DailyEntryPage
  # The day daily entry opens on, and the day its week view ends on, without a date: rain gauges
  # are read in the morning, and the reading is mostly yesterday's rain, so before noon (Central,
  # config.time_zone) yesterday, from noon on today
  def self.default_date
    (Time.current.hour < 12) ? Current.today - 1 : Current.today
  end

  def initialize(group, date)
    @group, @date = group, date
  end

  def farms
    @farms ||= @group.farms.order(:name).includes(:irrigation_groups,
      systems: [:weather_cell, :irrigation_group, {fields: {plantings: [:plant, :canopy_observations, :canopy_cuttings]}}]).to_a
  end

  def systems = farms.flat_map(&:systems)

  def fields = systems.flat_map(&:fields)

  def props
    {date: @date, farms: farms.map { |farm| farm_props(farm) }}
  end

  private

  def farm_props(farm)
    {id: farm.id, name: farm.name, use_model_precip: farm.use_model_precip,
     irrigation_groups: farm.irrigation_groups.map { |irrigation_group| irrigation_group.slice(:id, :name, :use_model_precip) },
     systems: farm.systems.map { |system| system_props(system) }}
  end

  def system_props(system)
    fields = fields_by_system.fetch(system.id, [])
    {id: system.id, name: system.name, kind: system.kind, kind_name: system.kind_name, irrigation_group_id: system.irrigation_group_id,
     pump_capacity_gpm: system.pump_capacity_gpm, inches_at_100: system.inches_at_100,
     yesterday: yesterday(fields),
     fields: fields.map { |field| field_props(system, field) }}
  end

  # The day before's irrigation on the fields and plots ({fields: {id => inches}, plantings: {id =>
  # inches}}), offered as "Same as yesterday" while none of them has any this day; nil for none
  def yesterday(fields)
    plots = fields.flat_map { |field| field.plantings_on(@date).select(&:partial?) }
    return if fields.any? { |field| field_entries[field.id]&.irrigation_in } ||
      plots.any? { |plot| planting_entries[plot.id]&.irrigation_in }
    before = {fields: fields.to_h { |field| [field.id, entries_before[field.id]&.irrigation_in] }.compact,
              plantings: plots.to_h { |plot| [plot.id, planting_entries_before[plot.id]&.irrigation_in] }.compact}
    before if before.values.any?(&:any?)
  end

  def field_props(system, field)
    {id: field.id, name: field.name, area_acres: field.area_acres,
     # Only as a hint where the balance would use it (Q7: not on a field using entered rain, through today)
     rain_model: (system.use_model_precip? || @date > Current.today) ? rain[system.weather_cell_id] : nil,
     entry: field_entries[field.id]&.slice(:rain_in, :irrigation_in, :soil_moisture_pct),
     plantings: field.plantings_on(@date).sort_by(&:order_key)
       .map { |planting| planting_props(planting) }}
  end

  def planting_props(planting)
    {id: planting.id, plant_name: planting.plant.name, variety: planting.variety, partial: planting.partial?,
     rainfed: planting.rainfed?,
     area_acres: planting.area_acres, plot_length_ft: planting.plot_length_ft, plot_width_ft: planting.plot_width_ft,
     entry: planting.partial? ? planting_entries[planting.id]&.slice(:irrigation_in, :soil_moisture_pct) : nil,
     cover: cover(planting)}
  end

  # The planting's canopy reading that day, and whether one is wanted: from emergence (or a cutting)
  # until the canopy closes or the vines are killed, and always when there's a reading that day.
  # nil when none is wanted.
  def cover(planting)
    lai = planting.et_method == "lai"
    reading = planting.canopy_observations.find { |obs| obs.date == @date }
    value = reading && (lai ? reading.lai : reading.pct_cover)
    task = PlantingTasks.canopy(planting, @date)
    wanted = @date >= planting.emergence_date && !(task && task.note && !task.due)
    return unless wanted || value

    {kind: lai ? "lai" : "pct_cover", value:, due: task&.due || false,
     # The reading before this day, for "last Jul 2" (a reading that day is shown as the value)
     last_date: (task&.last_date unless task&.last_date == @date)}
  end

  def fields_by_system
    @fields_by_system ||= fields.sort_by(&:name).group_by { |field| field.system_id_on(@date) }
  end

  def field_entries
    @field_entries ||= FieldEntry.where(field_id: fields.map(&:id), date: @date).index_by(&:field_id)
  end

  def entries_before
    @entries_before ||= FieldEntry.where(field_id: fields.map(&:id), date: @date - 1).where.not(irrigation_in: nil)
      .index_by(&:field_id)
  end

  def planting_entries
    @planting_entries ||= PlantingEntry.where(planting_id: fields.flat_map(&:plantings).map(&:id),
      date: @date).index_by(&:planting_id)
  end

  def planting_entries_before
    @planting_entries_before ||= PlantingEntry.where(planting_id: fields.flat_map(&:plantings).map(&:id),
      date: @date - 1).where.not(irrigation_in: nil).index_by(&:planting_id)
  end

  def rain
    @rain ||= WeatherDay.where(weather_cell_id: systems.map(&:weather_cell_id), date: @date)
      .pluck(:weather_cell_id, :precip_in).to_h
  end
end

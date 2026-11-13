# The props of daily entry (PLAN.md Phase 8 G.4) for one operation on one date: its farms, each
# with its irrigation groups and systems ("pivots" in code, G.5); each pivot's irrigation that day and its fields; each field's
# entry, the rain the model would use, and its plantings in season that day, with a part-field
# planting's own entry and each planting's canopy reading (when one is wanted: PlantingTasks.canopy).
# Each field is under the system it was on that day (Field#pivot_id_on: a season keeps the system
# it ran on, G.14 part 7), which for today is its own. Loads everything up front, with no query per
# field.
class DailyEntryPage
  def initialize(group, date)
    @group, @date = group, date
  end

  def farms
    @farms ||= @group.farms.order(:name).includes(:pivot_groups,
      pivots: [:weather_cell, {fields: {plantings: [:plant, :canopy_observations, :canopy_cuttings]}}]).to_a
  end

  def pivots = farms.flat_map(&:pivots)

  def fields = pivots.flat_map(&:fields)

  def props
    {date: @date, farms: farms.map { |farm| farm_props(farm) }}
  end

  private

  def farm_props(farm)
    {id: farm.id, name: farm.name,
     pivot_groups: farm.pivot_groups.map { |pivot_group| pivot_group.slice(:id, :name) },
     pivots: farm.pivots.map { |pivot| pivot_props(pivot) }}
  end

  def pivot_props(pivot)
    irrigation = irrigations[pivot.id]
    {id: pivot.id, name: pivot.name, kind: pivot.kind, kind_name: pivot.kind_name, pivot_group_id: pivot.pivot_group_id,
     pump_capacity_gpm: pivot.pump_capacity_gpm,
     irrigation: irrigation && PivotIrrigationSerializer.new(irrigation).to_h,
     fields: fields_by_pivot.fetch(pivot.id, []).map { |field| field_props(pivot, field) }}
  end

  def field_props(pivot, field)
    {id: field.id, name: field.name, area_acres: field.area_acres,
     # Only as a hint where the balance would use it (Q7: not on a field using entered rain, through today)
     rain_model: (field.effective_use_model_precip || @date > Date.current) ? rain[pivot.weather_cell_id] : nil,
     entry: field_entries[field.id]&.slice(:rain_in, :irrigation_in, :soil_moisture_pct),
     plantings: field.plantings_on(@date).sort_by { |planting| [planting.partial? ? 1 : 0, planting.season_start, planting.id] }
       .map { |planting| planting_props(planting) }}
  end

  def planting_props(planting)
    {id: planting.id, plant_name: planting.plant.name, variety: planting.variety, partial: planting.partial?,
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

  def fields_by_pivot
    @fields_by_pivot ||= fields.sort_by(&:name).group_by { |field| field.pivot_id_on(@date) }
  end

  def irrigations
    @irrigations ||= PivotIrrigation.where(pivot: pivots, date: @date).index_by(&:pivot_id)
  end

  def field_entries
    @field_entries ||= FieldEntry.where(field_id: fields.map(&:id), date: @date).index_by(&:field_id)
  end

  def planting_entries
    @planting_entries ||= PlantingEntry.where(planting_id: fields.flat_map(&:plantings).map(&:id),
      date: @date).index_by(&:planting_id)
  end

  def rain
    @rain ||= WeatherDay.where(weather_cell_id: pivots.map(&:weather_cell_id), date: @date)
      .pluck(:weather_cell_id, :precip_in).to_h
  end
end

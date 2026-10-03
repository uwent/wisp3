# Resolves what went into a field on each day, from the grower's entries, pivot irrigation, field
# group entries and weather, with where each value came from (PLAN.md §4 "Precedence"):
#
#   rain       = field entry ?? field group entry ?? (group uses model rain ? weather : 0.0)
#   irrigation = field entry ?? pivot irrigation (if it covers this field) ?? field group entry ?? 0.0
#   et0        = weather (nil → WaterBalance gap-fills)
#   moisture   = field entry ?? field group entry
#
# Sources: :entered, :pivot, :group, :model, :none (nothing entered and nothing modeled), and
# :missing (the model value should exist but doesn't, e.g. weather not fetched yet). A day
# with no moisture reading has moisture_source nil.
#
# weather: {date => {et0:, precip:}} (in/day); missing dates or values are nil.
class DailyInputs
  Day = Data.define(:date, :rain, :rain_source, :rain_model, :irrigation, :irrigation_source,
    :et0, :et0_source, :soil_moisture_pct, :moisture_source)

  def initialize(field, dates, weather: {})
    @field, @dates, @weather = field, dates, weather
  end

  def days
    entries = @field.field_entries.where(date: @dates).index_by(&:date)
    group_entries = group_entries_by_date
    pivot_irrigations = @field.pivot.pivot_irrigations.where(date: @dates)
      .select { |irrigation| irrigation.applies_to?(@field) }.index_by(&:date)

    @dates.map do |date|
      entry, group_entry, weather = entries[date], group_entries[date], @weather[date] || {}
      rain, rain_source = rain(entry, group_entry, weather)
      irrigation, irrigation_source = irrigation(entry, pivot_irrigations[date], group_entry)
      moisture, moisture_source = first_of([entry&.soil_moisture_pct, :entered], [group_entry&.soil_moisture_pct, :group], [nil, nil])

      Day.new(date:, rain:, rain_source:, rain_model: weather[:precip], irrigation:, irrigation_source:,
        et0: weather[:et0], et0_source: weather[:et0] ? :model : :missing,
        soil_moisture_pct: moisture, moisture_source:)
    end
  end

  private

  def rain(entry, group_entry, weather)
    modeled = if use_model_precip?
      [weather[:precip], weather[:precip] ? :model : :missing]
    else
      [0.0, :none]
    end
    first_of([entry&.rain_in, :entered], [group_entry&.rain_in, :group], modeled)
  end

  def irrigation(entry, pivot_irrigation, group_entry)
    first_of([entry&.irrigation_in, :entered], [pivot_irrigation&.applied_inches, :pivot],
      [group_entry&.irrigation_in, :group], [0.0, :none])
  end

  # The first [value, source] with a value; [nil, last source] if none has one
  def first_of(*candidates)
    candidates.find { |value, _| !value.nil? } || [nil, candidates.last.last]
  end

  def use_model_precip?
    @use_model_precip = @field.farm.group.use_model_precip if @use_model_precip.nil?
    @use_model_precip
  end

  # A field in several field groups takes each day's entry from the oldest group that has one
  def group_entries_by_date
    FieldGroupEntry.where(field_group_id: @field.field_group_ids, date: @dates)
      .order(:field_group_id).group_by(&:date).transform_values(&:first)
  end
end

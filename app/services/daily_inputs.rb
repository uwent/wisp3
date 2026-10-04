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
# weather: {date => {et0:, precip:}} (in/day); missing dates or values are nil. records: the field's
# entries, field group entries and pivot irrigations, from DailyInputs.preload (pages showing many
# fields load them once for all); without it they're queried here.
class DailyInputs
  Day = Data.define(:date, :rain, :rain_source, :rain_model, :irrigation, :irrigation_source,
    :et0, :et0_source, :soil_moisture_pct, :moisture_source)

  # One field's records over some dates. group_entries: every entry of the field's groups.
  Records = Data.define(:entries, :group_entries, :pivot_irrigations)

  # {field_id => Records} for fields over dates (a range), in four queries
  def self.preload(fields, dates)
    field_ids = fields.map(&:id)
    entries = FieldEntry.where(field_id: field_ids, date: dates).group_by(&:field_id)
    irrigations = PivotIrrigation.where(pivot_id: fields.map(&:pivot_id).uniq, date: dates).group_by(&:pivot_id)
    memberships = FieldGroupMember.where(field_id: field_ids).pluck(:field_id, :field_group_id)
      .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
    group_entries = FieldGroupEntry.where(field_group_id: memberships.values.flatten.uniq, date: dates)
      .group_by(&:field_group_id)

    fields.to_h do |field|
      [field.id, Records.new(entries: entries.fetch(field.id, []),
        group_entries: memberships.fetch(field.id, []).flat_map { |id| group_entries.fetch(id, []) },
        pivot_irrigations: irrigations.fetch(field.pivot_id, []))]
    end
  end

  def initialize(field, dates, weather: {}, records: nil)
    @field, @dates, @weather = field, dates, weather
    @records = records || Records.new(
      entries: @field.field_entries.where(date: span),
      group_entries: FieldGroupEntry.where(field_group_id: @field.field_group_ids, date: span),
      pivot_irrigations: @field.pivot.pivot_irrigations.where(date: span)
    )
  end

  def days
    return [] if @dates.empty?
    entries = @records.entries.index_by(&:date)
    group_entries = group_entries_by_date
    pivot_irrigations = @records.pivot_irrigations.select { |irrigation| irrigation.applies_to?(@field) }.index_by(&:date)

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

  # Queries cover first..last date (a range is far cheaper to build than a list of every date);
  # values are looked up by date, so dates in between that weren't asked for are never used
  def span = @dates.empty? ? Date.current...Date.current : @dates.min..@dates.max

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
    @use_model_precip = @field.pivot.farm.group.use_model_precip if @use_model_precip.nil?
    @use_model_precip
  end

  # A field in several field groups takes each day's entry from the oldest group that has one
  def group_entries_by_date
    @records.group_entries.sort_by(&:field_group_id).group_by(&:date).transform_values(&:first)
  end
end

# Resolves what went into a field on each day, from the grower's entries, pivot irrigation, field
# group entries and weather, with where each value came from (PLAN.md §4 "Precedence"):
#
#   rain       = field entry ?? field group entry ?? (group uses model rain ? weather : 0.0)
#   irrigation = field entry ?? pivot irrigation (if it covers this field) ?? field group entry ?? 0.0
#   et0        = weather (nil → WaterBalance gap-fills)
#   moisture   = field entry ?? field group entry
#
# For a planting on part of a field (planting:, PLAN.md Phase 8 G.11), its own entries come first
# and the field's are the field's, so:
#
#   irrigation = planting entry ?? field entry (:field) ?? pivot irrigation ?? field group entry ?? 0.0
#   moisture   = planting entry (a reading from elsewhere on the field isn't this crop's)
#   rain       = as above (rain falls on the whole field)
#
# Sources: :entered, :field, :pivot, :group, :model, :forecast (modeled, from the forecast: today and the
# days ahead), :none (nothing entered and nothing modeled), and :missing (the model value should
# exist but doesn't, e.g. weather not fetched yet). A day with no moisture reading has
# moisture_source nil.
#
# weather: {date => {et0:, precip:, forecast:}} (in/day; WeatherDay.balance_inputs); missing dates
# or values are nil. records: the field's
# entries, field group entries and pivot irrigations, from DailyInputs.preload (pages showing many
# fields load them once for all); without it they're queried here.
class DailyInputs
  Day = Data.define(:date, :rain, :rain_source, :rain_model, :irrigation, :irrigation_source,
    :et0, :et0_source, :soil_moisture_pct, :moisture_source)

  # One field's records over some dates. group_entries: every entry of the field's groups;
  # planting_entries: its part-field plantings' own entries.
  Records = Data.define(:entries, :group_entries, :pivot_irrigations, :planting_entries) do
    def initialize(entries:, group_entries:, pivot_irrigations:, planting_entries: []) = super
  end

  # {field_id => Records} for fields over dates (a range), in five queries
  def self.preload(fields, dates)
    field_ids = fields.map(&:id)
    entries = FieldEntry.where(field_id: field_ids, date: dates).group_by(&:field_id)
    planting_entries = PlantingEntry.joins(:planting).where(plantings: {field_id: field_ids}, date: dates)
      .select("planting_entries.*, plantings.field_id AS entry_field_id").group_by { |entry| entry[:entry_field_id] }
    irrigations = PivotIrrigation.where(pivot_id: fields.map(&:pivot_id).uniq, date: dates).group_by(&:pivot_id)
    memberships = FieldGroupMember.where(field_id: field_ids).pluck(:field_id, :field_group_id)
      .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
    group_entries = FieldGroupEntry.where(field_group_id: memberships.values.flatten.uniq, date: dates)
      .group_by(&:field_group_id)

    fields.to_h do |field|
      [field.id, Records.new(entries: entries.fetch(field.id, []),
        group_entries: memberships.fetch(field.id, []).flat_map { |id| group_entries.fetch(id, []) },
        pivot_irrigations: irrigations.fetch(field.pivot_id, []),
        planting_entries: planting_entries.fetch(field.id, []))]
    end
  end

  # today: days after it are the projection, which takes the forecast's rain even on a field that
  # uses only entered rain (nobody can enter rain ahead; Q7)
  # planting: the planting whose balance this is; a part-field one takes its own entries first
  def initialize(field, dates, weather: {}, records: nil, today: Date.current, planting: nil)
    @field, @dates, @weather, @today = field, dates, weather, today
    @part = planting if planting&.partial?
    @records = records || Records.new(
      entries: @field.field_entries.where(date: span),
      group_entries: FieldGroupEntry.where(field_group_id: @field.field_group_ids, date: span),
      pivot_irrigations: @field.pivot.pivot_irrigations.where(date: span),
      planting_entries: @part ? @part.planting_entries.where(date: span).to_a : []
    )
  end

  def days
    return [] if @dates.empty?
    entries = @records.entries.index_by(&:date)
    group_entries = group_entries_by_date
    pivot_irrigations = @records.pivot_irrigations.select { |irrigation| irrigation.applies_to?(@field) }.index_by(&:date)
    own = @part ? @records.planting_entries.select { |entry| entry.planting_id == @part.id }.index_by(&:date) : {}

    @dates.map do |date|
      entry, group_entry, weather = entries[date], group_entries[date], @weather[date] || {}
      rain, rain_source = rain(date, entry, group_entry, weather)
      irrigation, irrigation_source = irrigation(own[date], entry, pivot_irrigations[date], group_entry)
      moisture, moisture_source = moisture(own[date], entry, group_entry)

      Day.new(date:, rain:, rain_source:, rain_model: weather[:precip], irrigation:, irrigation_source:,
        et0: weather[:et0], et0_source: weather[:et0] ? model_source(weather) : :missing,
        soil_moisture_pct: moisture, moisture_source:)
    end
  end

  private

  # Queries cover first..last date (a range is far cheaper to build than a list of every date);
  # values are looked up by date, so dates in between that weren't asked for are never used
  def span = @dates.empty? ? Date.current...Date.current : @dates.min..@dates.max

  def rain(date, entry, group_entry, weather)
    modeled = if use_model_precip? || date > @today
      [weather[:precip], weather[:precip] ? model_source(weather) : :missing]
    else
      [0.0, :none]
    end
    first_of([entry&.rain_in, :entered], [group_entry&.rain_in, :group], modeled)
  end

  def irrigation(own, entry, pivot_irrigation, group_entry)
    first_of(*([[own&.irrigation_in, :entered]] if @part), [entry&.irrigation_in, @part ? :field : :entered],
      [pivot_irrigation&.applied_inches, :pivot], [group_entry&.irrigation_in, :group], [0.0, :none])
  end

  def moisture(own, entry, group_entry)
    return first_of([own&.soil_moisture_pct, :entered], [nil, nil]) if @part
    first_of([entry&.soil_moisture_pct, :entered], [group_entry&.soil_moisture_pct, :group], [nil, nil])
  end

  def model_source(weather) = weather[:forecast] ? :forecast : :model

  # The first [value, source] with a value; [nil, last source] if none has one
  def first_of(*candidates)
    candidates.find { |value, _| !value.nil? } || [nil, candidates.last.last]
  end

  def use_model_precip?
    @use_model_precip = @field.effective_use_model_precip if @use_model_precip.nil?
    @use_model_precip
  end

  # A field in several field groups takes each day's entry from the oldest group that has one
  def group_entries_by_date
    @records.group_entries.sort_by(&:field_group_id).group_by(&:date).transform_values(&:first)
  end
end

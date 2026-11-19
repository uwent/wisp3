# Resolves what went into a field on each day, from the grower's entries, pivot irrigation and
# weather, with where each value came from (PLAN.md §4 "Precedence"; field groups, a source between
# the field's entries and the model, were retired in Phase 8 G.4):
#
#   rain       = field entry ?? (its irrigation group, or farm, uses model rain ? weather : 0.0)
#   irrigation = field entry ?? pivot irrigation (if it covers this field) ?? 0.0
#
# The pivot irrigation is the system's the planting's season ran on (it keeps it when its field
# moves, G.14 part 7); for the field as a whole, its system that day (Field#pivot_id_on).
#   et0        = weather (nil → WaterBalance gap-fills)
#   moisture   = field entry
#   wind, rh_min = weather (they adjust the crop coefficient, CropEt.kc_mid; nil → FAO-56's standard)
#
# For a planting on part of a field (planting:, PLAN.md Phase 8 G.11), its own entries come first
# and the field's are the field's, so:
#
#   irrigation = planting entry ?? field entry (:field) ?? pivot irrigation ?? 0.0
#   moisture   = planting entry (a reading from elsewhere on the field isn't this crop's)
#   rain       = as above (rain falls on the whole field)
#
# Sources: :entered, :field, :pivot, :model, :forecast (modeled, from the forecast: today and the
# days ahead), :none (nothing entered and nothing modeled), and :missing (the model value should
# exist but doesn't, e.g. weather not fetched yet). A day with no moisture reading has
# moisture_source nil.
#
# weather: {date => {et0:, precip:, forecast:}} (in/day; WeatherDay.balance_inputs); missing dates
# or values are nil. records: the field's entries, its plantings' entries and its systems' irrigation,
# from DailyInputs.preload (pages showing many fields load them once for all); without it they're
# queried here.
class DailyInputs
  Day = Data.define(:date, :rain, :rain_source, :rain_model, :irrigation, :irrigation_source,
    :et0, :et0_source, :soil_moisture_pct, :moisture_source, :wind_mph, :rh_min_pct) do
    def initialize(wind_mph: nil, rh_min_pct: nil, **) = super
  end

  # One field's records over some dates. planting_entries: its part-field plantings' own entries.
  Records = Data.define(:entries, :pivot_irrigations, :planting_entries) do
    def initialize(entries:, pivot_irrigations:, planting_entries: []) = super
  end

  # {field_id => Records} for fields over dates (a range), in four queries (three more with run hours). A field's irrigation is
  # its system's and those its plantings over the dates ran on.
  def self.preload(fields, dates)
    field_ids = fields.map(&:id)
    entries = FieldEntry.where(field_id: field_ids, date: dates).group_by(&:field_id)
    planting_entries = PlantingEntry.joins(:planting).where(plantings: {field_id: field_ids}, date: dates)
      .select("planting_entries.*, plantings.field_id AS entry_field_id").group_by { |entry| entry[:entry_field_id] }
    pivot_ids = fields.to_h { |field| [field.id, [field.pivot_id]] }
    Planting.where(field_id: field_ids, season_start: ..dates.end, end_date: dates.begin..).distinct
      .pluck(:field_id, :pivot_id).each { |field_id, pivot_id| pivot_ids[field_id] |= [pivot_id] }
    irrigations = PivotIrrigation.where(pivot_id: pivot_ids.values.flatten.uniq, date: dates).to_a
    # Run hours convert over the system's plantings in season (irrigated_acres): loaded once per system
    ActiveRecord::Associations::Preloader.new(records: irrigations.select(&:run_hours),
      associations: {pivot: [:fields, {plantings: :field}]}).call
    irrigations = irrigations.group_by(&:pivot_id)

    fields.to_h do |field|
      [field.id, Records.new(entries: entries.fetch(field.id, []),
        pivot_irrigations: pivot_ids[field.id].flat_map { |pivot_id| irrigations.fetch(pivot_id, []) },
        planting_entries: planting_entries.fetch(field.id, []))]
    end
  end

  # today: days after it are the projection, which takes the forecast's rain even on a field that
  # uses only entered rain (nobody can enter rain ahead; Q7)
  # planting: the planting whose balance this is; a part-field one takes its own entries first
  def initialize(field, dates, weather: {}, records: nil, today: Current.today, planting: nil)
    @field, @dates, @weather, @today, @planting = field, dates, weather, today, planting
    @part = planting if planting&.partial?
    @records = records || Records.new(
      entries: @field.field_entries.where(date: span),
      pivot_irrigations: PivotIrrigation.where(pivot_id: planting ? planting.pivot_id : pivot_ids, date: span),
      planting_entries: @part ? @part.planting_entries.where(date: span).to_a : []
    )
  end

  def days
    return [] if @dates.empty?
    entries = @records.entries.index_by(&:date)
    pivot_irrigations = @records.pivot_irrigations.select { |irrigation| irrigation.covers?(@field.id) }
      .index_by { |irrigation| [irrigation.pivot_id, irrigation.date] }
    own = @part ? @records.planting_entries.select { |entry| entry.planting_id == @part.id }.index_by(&:date) : {}

    @dates.map do |date|
      entry, weather = entries[date], @weather[date] || {}
      rain, rain_source = rain(date, entry, weather)
      irrigation, irrigation_source = irrigation(own[date], entry, pivot_irrigations[[pivot_id_on(date), date]])
      moisture, moisture_source = moisture(own[date], entry)

      Day.new(date:, rain:, rain_source:, rain_model: weather[:precip], irrigation:, irrigation_source:,
        et0: weather[:et0], et0_source: weather[:et0] ? model_source(weather) : :missing,
        soil_moisture_pct: moisture, moisture_source:, wind_mph: weather[:wind], rh_min_pct: weather[:rh_min])
    end
  end

  private

  # Queries cover first..last date (a range is far cheaper to build than a list of every date);
  # values are looked up by date, so dates in between that weren't asked for are never used
  def span = @dates.empty? ? Date.current...Date.current : @dates.min..@dates.max

  # The system whose irrigation counts that day: the planting's, else the field's then
  def pivot_id_on(date) = @planting ? @planting.pivot_id : @field.pivot_id_on(date)

  # Every system the field was on over the dates
  def pivot_ids = @dates.map { |date| @field.pivot_id_on(date) }.uniq

  def rain(date, entry, weather)
    modeled = if use_model_precip? || date > @today
      [weather[:precip], weather[:precip] ? model_source(weather) : :missing]
    else
      [0.0, :none]
    end
    first_of([entry&.rain_in, :entered], modeled)
  end

  def irrigation(own, entry, pivot_irrigation)
    first_of(*([[own&.irrigation_in, :entered]] if @part), [entry&.irrigation_in, @part ? :field : :entered],
      [pivot_irrigation&.applied_inches, :pivot], [0.0, :none])
  end

  def moisture(own, entry)
    return first_of([own&.soil_moisture_pct, :entered], [nil, nil]) if @part
    first_of([entry&.soil_moisture_pct, :entered], [nil, nil])
  end

  def model_source(weather) = weather[:forecast] ? :forecast : :model

  # The first [value, source] with a value; [nil, last source] if none has one
  def first_of(*candidates)
    candidates.find { |value, _| !value.nil? } || [nil, candidates.last.last]
  end

  # The planting's system's setting, or for the field as a whole its system's now (Q7)
  def use_model_precip?
    @use_model_precip = (@planting || @field.pivot).use_model_precip? if @use_model_precip.nil?
    @use_model_precip
  end
end

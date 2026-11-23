# Resolves what went into a field on each day, from the grower's entries and weather, with where
# each value came from (docs/engine.md, A day):
#
#   rain       = field entry ?? (its irrigation group, or farm, uses model rain ? weather : 0.0)
#   irrigation = field entry ?? 0.0 (stored per field and plot, never inherited from the system: D15)
#   et0        = weather (nil → WaterBalance gap-fills)
#   moisture   = field entry
#   wind, rh_min = weather (they adjust the crop coefficient, CropEt.kc_mid; nil → FAO-56's standard)
#
# For a planting on part of a field (planting:), its own entries take the
# field's place for irrigation and moisture:
#
#   irrigation = planting entry ?? 0.0 (saving the field's also sets its plots that had the field's)
#   moisture   = planting entry (a reading from elsewhere on the field isn't this crop's)
#   rain       = as above (rain falls on the whole field)
#
# Sources: :entered, :model, :forecast (modeled, from the forecast: today and the days ahead), :none
# (nothing entered and nothing modeled), and :missing (the model value should exist but doesn't,
# e.g. weather not fetched yet). A day with no moisture reading has moisture_source nil.
#
# weather: {date => {et0:, precip:, forecast:}} (in/day; WeatherDay.balance_inputs); missing dates
# or values are nil. records: the field's entries and its plantings' entries, from
# DailyInputs.preload (pages showing many fields load them once for all); without it they're
# queried here.
class DailyInputs
  Day = Data.define(:date, :rain, :rain_source, :rain_model, :irrigation, :irrigation_source,
    :et0, :et0_source, :soil_moisture_pct, :moisture_source, :wind_mph, :rh_min_pct) do
    def initialize(wind_mph: nil, rh_min_pct: nil, **) = super
  end

  # One field's records over some dates. planting_entries: its part-field plantings' own entries.
  Records = Data.define(:entries, :planting_entries) do
    def initialize(entries:, planting_entries: []) = super
  end

  # {field_id => Records} for fields over dates (a range), in two queries
  def self.preload(fields, dates)
    field_ids = fields.map(&:id)
    entries = FieldEntry.where(field_id: field_ids, date: dates).group_by(&:field_id)
    planting_entries = PlantingEntry.joins(:planting).where(plantings: {field_id: field_ids}, date: dates)
      .select("planting_entries.*, plantings.field_id AS entry_field_id").group_by { |entry| entry[:entry_field_id] }

    fields.to_h do |field|
      [field.id, Records.new(entries: entries.fetch(field.id, []), planting_entries: planting_entries.fetch(field.id, []))]
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
      planting_entries: @part ? @part.planting_entries.where(date: span).to_a : []
    )
  end

  def days
    return [] if @dates.empty?
    entries = @records.entries.index_by(&:date)
    own = @part ? @records.planting_entries.select { |entry| entry.planting_id == @part.id }.index_by(&:date) : {}

    @dates.map do |date|
      entry, weather = entries[date], @weather[date] || {}
      rain, rain_source = rain(date, entry, weather)
      irrigation, irrigation_source = irrigation(own[date], entry)
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

  def rain(date, entry, weather)
    modeled = if use_model_precip? || date > @today
      [weather[:precip], weather[:precip] ? model_source(weather) : :missing]
    else
      [0.0, :none]
    end
    first_of([entry&.rain_in, :entered], modeled)
  end

  def irrigation(own, entry)
    first_of([(@part ? own : entry)&.irrigation_in, :entered], [0.0, :none])
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

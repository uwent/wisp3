# A crop's default percent cover curve (PLAN.md Phase 6.7), from db/reference/canopy_curves.yml:
# FAO AquaCrop's canopy growth since emergence, then an AquaCrop decline or a calendar rule (potato's
# late-summer decline). The file documents the equations and each crop's sources; Canopy combines a
# curve with the readings a grower enters.
#
# Time since emergence is growing degree days (PLAN.md §9 C23) when the curve has thermal
# parameters and is given a clock (ThermalTime, for the planting's weather cell), else calendar
# days. The thermal parameters reproduce the calendar curve in a typical Central Wisconsin season
# for the crop's typical emergence date, so a warm spring runs the canopy ahead of the calendar and a
# cool one behind it (docs/canopy/07-thermal-time.md).
class CanopyCurve
  FILE = Rails.root.join("db/reference/canopy_curves.yml")
  CONFIDENCE = {
    "matches_wi" => "Published; matches Wisconsin 2026 readings",
    "adjusted_wi" => "Published, adjusted to Wisconsin 2026 readings",
    "fitted_wi" => "Fitted to Wisconsin 2026 readings",
    "published" => "Published; not yet checked in Wisconsin",
    "fao56" => "Derived from FAO-56 stage lengths; not yet checked in Wisconsin",
    "generic" => "Generic shape for crops without their own curve; readings correct it"
  }.freeze
  # A planting's choice of no curve at all: readings only (PLAN.md Phase 8 G.3)
  NONE = "none"
  # The canopy counts as full (for a decline rule's start) at this share of its maximum
  FULL = 0.98

  Source = Data.define(:id, :citation, :url)
  # In degree days (°C days, Weather::DegreeDays.aquacrop): base and upper temperatures (°C), growth
  # coefficient per degree day, and for an aquacrop decline, its start and coefficient per degree
  # day. emergence: the typical date ("05-15") the calendar curve was converted at; basis: how.
  Thermal = Data.define(:base_c, :upper_c, :cgc, :decline_start, :cdc, :emergence, :basis) do
    def initialize(decline_start: nil, cdc: nil, **) = super
  end

  attr_reader :key, :cc0, :ccx, :cgc, :decline, :basis, :confidence, :sources, :notes
  # Typical days from emergence to harvest, and how they were worked out (PLAN.md Phase 8 G.2)
  attr_reader :season_days, :season_basis
  # A generic curve's name ("Vegetable, medium") and the crops that follow it by default (G.3)
  attr_reader :name, :default_for
  # Its Thermal parameters, or nil if it runs only by calendar days
  attr_reader :thermal
  # Changes with the curve's definition, so fits to it are redone (CanopyFit.fetch)
  attr_reader :digest

  # Whether plantings of the crop take a vine kill date (potato): the canopy ramps down from it while
  # the balance runs on to harvest
  def vine_kill? = @vine_kill

  class << self
    # The curve for a plant key, or nil if the crop has none
    def for(key) = all[key]

    def all = @all ||= load("crops")

    # The generic curves (G.3), in the file's order
    def generic = @generic ||= load("generic")

    # The generic curve a crop without its own follows unless its planting picks another, or nil
    def default_generic(plant_key) = generic.values.find { |curve| curve.default_for.include?(plant_key) }

    # The percent cover curve a planting of plant_key follows: the crop's own, else the generic one
    # chosen (choice: a generic key, NONE, or nil for the crop's default)
    def effective(plant_key, choice = nil)
      all[plant_key] || ((choice == NONE) ? nil : (choice && generic[choice]) || default_generic(plant_key))
    end

    private

    def load(section)
      data = YAML.safe_load_file(FILE, aliases: true)
      sources = data.fetch("sources").to_h { |id, source| [id, Source.new(id:, **source.symbolize_keys)] }
      data.fetch(section).to_h { |key, crop| [key, new(key, crop, sources)] }.freeze
    end
  end

  def initialize(key, definition, sources)
    @key = key
    growth = definition.fetch("growth")
    @cc0, @ccx, @cgc = growth.fetch("cc0"), growth.fetch("ccx"), growth.fetch("cgc")
    @decline = definition["decline"]&.symbolize_keys
    @basis, @notes = definition.fetch("basis"), definition["notes"]
    @digest = Digest::SHA256.hexdigest(definition.slice("growth", "decline", "thermal").to_json).first(12)
    @thermal = definition["thermal"]&.then { |thermal| Thermal.new(**thermal.symbolize_keys) }
    if @thermal && @decline&.fetch(:type) == "aquacrop" && !(@thermal.decline_start && @thermal.cdc)
      raise ArgumentError, "#{key}: thermal parameters need the decline's start and cdc"
    end
    @vine_kill = definition.fetch("vine_kill", false)
    @season_days, @season_basis = definition["season"]&.values_at("days", "basis")
    @name, @default_for = definition["name"], definition.fetch("default_for", [])
    @confidence = definition.fetch("confidence")
    raise ArgumentError, "#{key}: unknown confidence #{@confidence}" unless CONFIDENCE.key?(@confidence)
    @sources = definition.fetch("sources").map { |id| sources.fetch(id) }
  end

  def confidence_label = CONFIDENCE.fetch(confidence)

  # Percent cover on date for a crop that emerged on emergence_date (0 before it). Fitted to a
  # planting's readings (CanopyFit), the curve can run shift days later (earlier if negative), grow
  # stretch times slower and reach height times its cover (up to 100%); potato's calendar decline
  # keeps its date. clock: a ThermalTime for the planting's cell, to run in degree days (ignored
  # without thermal parameters); a shift then moves the day the degree days start from.
  def cover(emergence_date, date, **) = from(emergence_date, **).call(date)

  # The curve as a function of date, for Canopy
  def from(emergence_date, shift: 0, stretch: 1.0, height: 1.0, clock: nil)
    clock = nil unless thermal
    start = emergence_date + shift
    rate = clock ? thermal.cgc : cgc
    full = nil
    lambda do |date|
      next 0.0 if date < emergence_date
      tau = (clock ? clock.between(start, date) : (date - start).to_i) / stretch.to_f
      declined = declined(date, tau, clock) { full ||= full_date(start, stretch, clock) }
      [100 * [growth(tau, rate), declined].compact.min * height, 100.0].min
    end
  end

  # The clock the curve runs on at a cell (CellTemperatures): its ThermalTime, or nil to run by
  # calendar days (no thermal parameters, or no normals for the cell yet)
  def clock(temperatures)
    thermal && temperatures&.thermal_time(base_c: thermal.base_c, upper_c: thermal.upper_c)
  end

  # Days from emergence until the canopy is full (FULL of its maximum), by the calendar curve
  def full_day = full_time(cgc).ceil

  # The last day before the curve's decline (cover falls the day after), or nil for a crop without
  # one: the start of FAO-56's late season, when the crop coefficient eases toward harvest's (C22,
  # WaterBalance::Crop). Same terms as #from, clock included (C23); potato's rule date is in the
  # emergence year.
  def decline_start(emergence_date, shift: 0, stretch: 1.0, clock: nil)
    clock = nil unless thermal
    start = emergence_date + shift
    case decline&.fetch(:type)
    when "aquacrop"
      return emergence_date + (shift + stretch * decline.fetch(:start_day)).floor unless clock
      needed = stretch * thermal.decline_start
      # The last day the degree days since the start haven't passed the decline's (#declined)
      (0..366).lazy.map { |days| start + days }.find { |date| clock.between(start, date + 1) > needed } || start + 366
    when "rule"
      month, day = decline.fetch(:date).split("-").map(&:to_i)
      [Date.new(emergence_date.year, month, day), full_date(start, stretch, clock)].max
    end
  end

  private

  # Time from emergence (days, or degree days at that growth rate) until the canopy is full
  def full_time(rate) = Math.log(ccx / (4 * (1 - FULL) * cc0)) / rate

  # The day the canopy is full, for a curve starting on start (emergence after any shift)
  def full_date(start, stretch, clock)
    return start + (stretch * full_day).round unless clock
    needed = stretch * full_time(thermal.cgc)
    # A year's degree days fill any canopy; the limit only guards against a cell too cold to grow one
    (0..366).lazy.map { |days| start + days }.find { |date| clock.between(start, date) >= needed } || start + 366
  end

  def growth(t, rate)
    cc = cc0 * Math.exp(rate * t)
    cc = ccx - 0.25 * ccx * ccx / cc0 * Math.exp(-rate * t) if cc > ccx / 2
    cc.clamp(0.0, ccx)
  end

  # The decline's cover (fraction) on date, or nil before it starts. t: time of growth (after any
  # fit), days or degree days by the clock; the block gives the day the canopy is full (for a rule).
  def declined(date, t, clock)
    case decline&.fetch(:type)
    when "aquacrop"
      start_at, rate = clock ? [thermal.decline_start, thermal.cdc] : decline.values_at(:start_day, :cdc)
      since = t - start_at
      return if since <= 0
      (ccx * (1 - 0.05 * (Math.exp(3.33 * rate * since / (ccx + 2.29)) - 1))).clamp(0.0, ccx)
    when "rule"
      month, day = decline.fetch(:date).split("-").map(&:to_i)
      start = Date.new(date.year, month, day)
      return if date <= start
      start = [start, yield].max
      return if date <= start
      # Smoothstep: level at both ends, so it leaves full cover and meets the floor without a corner
      x = [(date - start).to_f / decline.fetch(:days), 1.0].min
      ccx - (ccx - decline.fetch(:floor) / 100.0) * (3 * x**2 - 2 * x**3)
    end
  end
end

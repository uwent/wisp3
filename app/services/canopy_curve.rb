# A crop's default percent cover curve (PLAN.md Phase 6.7), from db/reference/canopy_curves.yml:
# FAO AquaCrop's canopy growth by days since emergence, then an AquaCrop decline or a calendar rule
# (potato's late-summer decline). The file documents the equations and each crop's sources; Canopy
# combines a curve with the readings a grower enters.
class CanopyCurve
  FILE = Rails.root.join("db/reference/canopy_curves.yml")
  CONFIDENCE = {
    "matches_wi" => "Published; matches Wisconsin 2026 readings",
    "adjusted_wi" => "Published, adjusted to Wisconsin 2026 readings",
    "fitted_wi" => "Fitted to Wisconsin 2026 readings",
    "published" => "Published; not yet checked in Wisconsin",
    "fao56" => "Derived from FAO-56 stage lengths; not yet checked in Wisconsin"
  }.freeze
  # The canopy counts as full (for a decline rule's start) at this share of its maximum
  FULL = 0.98

  Source = Data.define(:id, :citation, :url)

  attr_reader :key, :cc0, :ccx, :cgc, :decline, :basis, :confidence, :sources, :notes
  # Changes with the curve's definition, so fits to it are redone (CanopyFit.fetch)
  attr_reader :digest

  # Whether plantings of the crop take a vine kill date (potato): the canopy ramps down from it while
  # the balance runs on to harvest
  def vine_kill? = @vine_kill

  class << self
    # The curve for a plant key, or nil if the crop has none
    def for(key) = all[key]

    def all = @all ||= load

    private

    def load
      data = YAML.safe_load_file(FILE, aliases: true)
      sources = data.fetch("sources").to_h { |id, source| [id, Source.new(id:, **source.symbolize_keys)] }
      data.fetch("crops").to_h { |key, crop| [key, new(key, crop, sources)] }.freeze
    end
  end

  def initialize(key, definition, sources)
    @key = key
    growth = definition.fetch("growth")
    @cc0, @ccx, @cgc = growth.fetch("cc0"), growth.fetch("ccx"), growth.fetch("cgc")
    @decline = definition["decline"]&.symbolize_keys
    @basis, @notes = definition.fetch("basis"), definition["notes"]
    @digest = Digest::SHA256.hexdigest(definition.slice("growth", "decline").to_json).first(12)
    @vine_kill = definition.fetch("vine_kill", false)
    @confidence = definition.fetch("confidence")
    raise ArgumentError, "#{key}: unknown confidence #{@confidence}" unless CONFIDENCE.key?(@confidence)
    @sources = definition.fetch("sources").map { |id| sources.fetch(id) }
  end

  def confidence_label = CONFIDENCE.fetch(confidence)

  # Percent cover on date for a crop that emerged on emergence_date (0 before it). Fitted to a
  # planting's readings (CanopyFit), the curve can run shift days later (earlier if negative), grow
  # stretch times slower and reach height times its cover (up to 100%); potato's calendar decline
  # keeps its date.
  def cover(emergence_date, date, shift: 0, stretch: 1.0, height: 1.0)
    t = (date - emergence_date).to_i
    return 0.0 if t.negative?
    tau = (t - shift) / stretch.to_f
    [100 * [growth(tau), declined(emergence_date, date, tau, shift:, stretch:)].compact.min * height, 100.0].min
  end

  # The curve as a function of date, for Canopy
  def from(emergence_date, **fit) = ->(date) { cover(emergence_date, date, **fit) }

  # Days from emergence until the canopy is full (FULL of its maximum)
  def full_day = (Math.log(ccx / (4 * (1 - FULL) * cc0)) / cgc).ceil

  private

  def growth(t)
    cc = cc0 * Math.exp(cgc * t)
    cc = ccx - 0.25 * ccx * ccx / cc0 * Math.exp(-cgc * t) if cc > ccx / 2
    cc.clamp(0.0, ccx)
  end

  # The decline's cover (fraction) on date, or nil before it starts. t: days of growth (after any fit).
  def declined(emergence_date, date, t, shift:, stretch:)
    case decline&.fetch(:type)
    when "aquacrop"
      since = t - decline.fetch(:start_day)
      return if since <= 0
      (ccx * (1 - 0.05 * (Math.exp(3.33 * decline.fetch(:cdc) * since / (ccx + 2.29)) - 1))).clamp(0.0, ccx)
    when "rule"
      month, day = decline.fetch(:date).split("-").map(&:to_i)
      start = [Date.new(date.year, month, day), emergence_date + (shift + stretch * full_day).round].max
      return if date <= start
      # Smoothstep: level at both ends, so it leaves full cover and meets the floor without a corner
      x = [(date - start).to_f / decline.fetch(:days), 1.0].min
      ccx - (ccx - decline.fetch(:floor) / 100.0) * (3 * x**2 - 2 * x**3)
    end
  end
end

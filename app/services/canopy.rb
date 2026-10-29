# A planting's canopy (percent cover, or LAI) on each day (PLAN.md §5.3, Phase 6.7).
#
# Before emergence and after end_date the canopy is 0. With no readings it follows the crop's curve
# (CanopyCurve for percent cover, CanopyModel for LAI), or is 0 if the crop has none. Readings
# dated before emergence are ignored (for perennials, use the green-up date as emergence).
#
# With readings, by the planting's setting:
# - following the curve (the default where there is one): the curve times a ratio, reading ÷
#   curve at each reading and 1 at emergence, linear between readings and held after the last. It
#   passes through every reading and keeps the curve's shape between and after them (including its
#   decline); backtested in docs/canopy/04-backtest.md. It never exceeds the larger of the curve's
#   peak and the highest reading.
# - straight lines (or no curve): linear from 0 at emergence through the readings, the last held
#   until end_date (legacy held it for only 6 days, C3).
#
# Vine kill (potato): from the vine kill date the canopy ramps down linearly to 0 over VINE_KILL_DAYS,
# from its value that day, then stays 0 until end_date (harvest). A reading on or after vine kill is
# taken as is on its day, and the ramp continues from it to the same end. Those readings are left
# out of the curve and the check, which describe the living canopy.
#
# check flags readings that disagree with the curve (percent cover only): see #check. PlantingTasks
# words it for the field page, dashboard and digest.
class Canopy
  # Readings this many days ahead of or behind the curve get a warning
  SHIFT_WARNING_DAYS = 7
  # A reading this many points below the one before, while the curve is still growing, gets one too
  DROP_WARNING = 5.0
  # Readings in this range of cover say how far along the canopy is (below it the curve is too flat,
  # above it growers stop at 80%)
  SHIFT_RANGE = (10.0...80.0)
  MAX_SHIFT = 30
  # Days from vine kill until the canopy is gone (desiccant; it varies a little by cultivar)
  VINE_KILL_DAYS = 14

  # days_ahead: how many days ahead of the curve the readings run (negative: behind), when beyond
  # SHIFT_WARNING_DAYS. drop: {date:, from:, to:}, the first reading that fell while the curve grew.
  Check = Data.define(:days_ahead, :drop)

  attr_reader :curve

  # curve: date → value, or nil. floor: the curve value below which a reading's ratio is taken
  # against this instead (the curve is near 0 just after emergence).
  def initialize(emergence_date:, end_date:, observations: [], curve: nil, follow_curve: true, floor: 1.0,
    check: false, vine_kill: nil)
    @emergence_date, @end_date, @curve, @floor, @check, @vine_kill = emergence_date, end_date, curve, floor, check, vine_kill
    readings = observations.select { |date, _| date >= emergence_date }.sort_by(&:first)
    @readings, @kill_readings = readings.partition { |date, _| vine_kill.nil? || date < vine_kill }
    @follow = curve && follow_curve && @readings.any?
    @anchors = @follow ? ratio_anchors : linear_anchors
  end

  # For a Planting, from its canopy observations (percent cover or LAI, by its ET method)
  def self.for(planting)
    lai = planting.et_method == "lai"
    attribute = lai ? :lai : :pct_cover
    observations = planting.canopy_observations.filter_map { |obs| [obs.date, obs[attribute]] if obs[attribute] }
    curve = if lai
      CanopyModel.from(planting.plant.canopy_model, planting.emergence_date)
    else
      CanopyCurve.for(planting.plant.key)&.from(planting.emergence_date)
    end
    new(emergence_date: planting.emergence_date, end_date: planting.end_date, observations:, curve:,
      follow_curve: planting.canopy_interpolation != "linear", floor: lai ? 0.05 : 1.0, check: !lai,
      vine_kill: planting.vine_kill_date)
  end

  def on(date)
    return 0.0 if date < @emergence_date || date > @end_date
    return killed(date) if @vine_kill && date >= @vine_kill

    living(date)
  end

  # The crop's curve on date, within the season (0 outside it), or nil without one. It doesn't ramp
  # down at vine kill: it's the typical living canopy, shown beside the modeled one.
  def curve_on(date)
    return unless curve
    (date < @emergence_date || date > @end_date) ? 0.0 : curve.call(date)
  end

  # Whether readings disagree with the curve: a Check, or nil if they don't (or can't be compared)
  def check
    return unless @check && curve
    return @result if defined?(@result)
    days_ahead, drop = shift, first_drop
    @result = (days_ahead || drop) ? Check.new(days_ahead:, drop:) : nil
  end

  private

  # The canopy before vine kill: the curve, the readings, or both
  def living(date)
    return curve_on(date) || 0.0 if @readings.empty?
    return [interpolate(date) * curve_on(date), cap].min if @follow

    interpolate(date)
  end

  # From vine kill (or the latest reading since), straight down to 0 at vine kill + VINE_KILL_DAYS
  def killed(date)
    start, value = @kill_readings.rfind { |reading_date, _| reading_date <= date } || [@vine_kill, living(@vine_kill)]
    return value if date == start

    remaining = (@vine_kill + VINE_KILL_DAYS - start).to_i
    return 0.0 unless remaining.positive?
    [value * (1 - (date - start).to_f / remaining), 0.0].max
  end

  # [[date, value]] interpolated linearly in time and held after the last
  def interpolate(date)
    after = @anchors.index { |anchor_date, _| anchor_date >= date }
    return @anchors.last.last unless after
    return @anchors[after].last if @anchors[after].first == date

    (date0, value0), (date1, value1) = @anchors[after - 1], @anchors[after]
    value0 + (value1 - value0) * (date - date0) / (date1 - date0)
  end

  def linear_anchors
    anchors = @readings.dup
    anchors.unshift([@emergence_date, 0.0]) if anchors.any? && anchors.first.first > @emergence_date
    anchors
  end

  def ratio_anchors
    anchors = @readings.map { |date, value| [date, value / [curve.call(date), @floor].max] }
    anchors.unshift([@emergence_date, 1.0]) if anchors.first.first > @emergence_date
    anchors
  end

  def cap
    @cap ||= [(@emergence_date..@end_date).map { |date| curve.call(date) }.max, @readings.map(&:last).max].max
  end

  # Days the readings between 10% and 80% run ahead of the curve, if beyond SHIFT_WARNING_DAYS: the
  # shift that fits them best (least squares)
  def shift
    growing = @readings.select { |_, value| SHIFT_RANGE.cover?(value) }
    return if growing.size < 2
    best = (-MAX_SHIFT..MAX_SHIFT).min_by do |days|
      [growing.sum { |date, value| (value - curve.call(date + days))**2 }, days.abs]
    end
    best if best.abs > SHIFT_WARNING_DAYS
  end

  def first_drop
    @readings.each_cons(2) do |(date0, value0), (date1, value1)|
      next unless value1 < value0 - DROP_WARNING && curve.call(date1) >= curve.call(date0)
      return {date: date1, from: value0, to: value1}
    end
    nil
  end
end

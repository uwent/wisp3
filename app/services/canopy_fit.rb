# Fits a crop's canopy curve to a planting's readings (docs/canopy/06-fitting.md): the curve can run
# some days later or earlier (shift), grow slower or faster (stretch) and be fuller or thinner
# (height). Each is held toward the typical curve by how much crops vary from field to field, and
# each reading pulls by how far it is from the curve over how precise a reading is, so one or two
# readings barely move the curve and many readings fit it closely (a penalized least squares fit,
# the same as a Bayesian fit with a normal prior on each). Canopy then passes through the readings.
module CanopyFit
  # shift: days later (earlier if negative); stretch: > 1 grows slower; height: > 1 fuller
  Fit = Data.define(:shift, :stretch, :height) do
    def typical? = shift.zero? && (stretch - 1).abs < 1e-9 && (height - 1).abs < 1e-9
  end
  TYPICAL = Fit.new(shift: 0, stretch: 1.0, height: 1.0)

  # How far crops typically run from their curve: about 5 days, 15% in growth rate, 10% in height
  SHIFT_SD = 5.0
  STRETCH_SD = 0.15 # of log stretch
  HEIGHT_SD = 0.10 # of log height
  # A reading's precision: 10 points of percent cover (Wisconsin 2026 readings scatter 4–9 points
  # around their own best-fitting curves; by eye, with emergence dates that may be off, likely more),
  # and LAI the same share of its peak. Accuracy barely changed from 5 to 15 points in the backtest;
  # at 10 a single reading moves the curve 0.6 days on average.
  COVER_NOISE = 10.0
  LAI_NOISE = 0.4
  # Percent cover readings at or above this say only "at least this": growers stop and hold there
  COVER_CENSOR = 80.0

  # The search: shifts of up to MAX_SHIFT days, and stretch and height in steps of e^STEP (stretch up
  # to e^±0.3, about ±35%; height e^±0.2, about ±20%), on a coarse grid and then around its best.
  # Deterministic, and the same as docs/canopy/scripts/backtest.py.
  MAX_SHIFT = 15
  STRETCH_STEPS = 6
  HEIGHT_STEPS = 4
  STEP = 0.05
  # Fits are kept until their readings change (or the curve, which is in the key)
  CACHE_FOR = 7.days

  module_function

  # readings: [[date, value]]; curve: ->(shift:, stretch:, height:) { ->(date) { value } }
  def run(readings, curve:, noise:, censor_at: nil)
    return TYPICAL if readings.empty?

    costs = Hash.new do |memo, (shift, ks, kh)|
      fitted = curve.call(shift:, stretch: Math.exp(ks * STEP), height: Math.exp(kh * STEP))
      misses = readings.sum do |date, value|
        model = fitted.call(date)
        miss = (censor_at && value >= censor_at) ? [censor_at - model, 0.0].max : value - model
        (miss / noise)**2
      end
      memo[[shift, ks, kh]] = misses + (shift / SHIFT_SD)**2 + (ks * STEP / STRETCH_SD)**2 + (kh * STEP / HEIGHT_SD)**2
    end
    coarse = grid(-MAX_SHIFT..MAX_SHIFT, -STRETCH_STEPS..STRETCH_STEPS, -HEIGHT_STEPS..HEIGHT_STEPS, step: [3, 2, 2])
    shift, ks, kh = coarse.min_by { |point| costs[point] }
    fine = grid([shift - 2, -MAX_SHIFT].max..[shift + 2, MAX_SHIFT].min,
      [ks - 1, -STRETCH_STEPS].max..[ks + 1, STRETCH_STEPS].min, [kh - 1, -HEIGHT_STEPS].max..[kh + 1, HEIGHT_STEPS].min)
    shift, ks, kh = fine.min_by { |point| costs[point] }
    Fit.new(shift:, stretch: Math.exp(ks * STEP), height: Math.exp(kh * STEP))
  end

  # run, kept in Rails.cache: key identifies the curve (its crop, definition and emergence date)
  def fetch(key, readings, curve:, noise:, censor_at: nil)
    return TYPICAL if readings.empty?
    cache_key = ["canopy-fit", *key, noise, censor_at, Digest::SHA256.hexdigest(readings.inspect)]
    Fit.new(**Rails.cache.fetch(cache_key, expires_in: CACHE_FOR) { run(readings, curve:, noise:, censor_at:).to_h })
  end

  def grid(shifts, stretches, heights, step: [1, 1, 1])
    shifts.step(step[0]).to_a.product(stretches.step(step[1]).to_a, heights.step(step[2]).to_a)
  end
end

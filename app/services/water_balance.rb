# The checkbook water balance for one planting (PLAN.md §5). Plain Ruby, no ActiveRecord: give it
# the planting's parameters and its resolved days, get back one result per day. Depths are inches.
#
# AD (allowable depletion) is the water above the MAD trigger point: AD_max at field capacity,
# 0 at the trigger, AD_pwp at the wilting point.
#
# Ported from legacy ADCalculator / FieldDailyWeather#old_update_balances, with fixes:
# - C2: a moisture reading resets AD capped at AD_max (legacy: TAW) and floored at AD_pwp, with
#   the excess recorded as deep drainage.
# - C6/C7: missing et0 is gap-filled from computed days only (legacy fed filled values back).
# - No truncation of small drainage (legacy zeroed drainage under 0.01 and ignored excess
#   under 0.00001); outputs are rounded to 4 places instead.
module WaterBalance
  GAP_FILL_DAYS = 7 # gap fill: mean of the top GAP_FILL_TOP adjusted ETs in the previous 7 days
  GAP_FILL_TOP = 3
  PRECISION = 4

  # FC and PWP are fractions; MRZD inches; MAD a fraction; percents are 0–100
  Params = Data.define(:field_capacity, :perm_wilting_pt, :max_root_zone_depth, :mad_frac, :et_method,
    :target_ad_pct, :initial_moisture_pct) do
    def initialize(field_capacity:, perm_wilting_pt:, max_root_zone_depth:, mad_frac:, et_method: "pct_cover",
      target_ad_pct: nil, initial_moisture_pct: nil)
      unless perm_wilting_pt.positive? && perm_wilting_pt < field_capacity && field_capacity < 1
        raise ArgumentError, "need 0 < wilting point < field capacity < 1"
      end
      raise ArgumentError, "root zone depth must be positive" unless max_root_zone_depth.positive?
      raise ArgumentError, "MAD must be between 0 and 1" unless mad_frac.positive? && mad_frac < 1
      super
    end

    def self.for(planting)
      field = planting.field
      new(field_capacity: field.effective_field_capacity, perm_wilting_pt: field.effective_perm_wilting_pt,
        max_root_zone_depth: planting.max_root_zone_depth, mad_frac: planting.mad_frac,
        et_method: planting.et_method, target_ad_pct: planting.target_ad_pct,
        initial_moisture_pct: planting.initial_moisture_pct)
    end

    # Total available water, field capacity to wilting point
    def taw = (field_capacity - perm_wilting_pt) * max_root_zone_depth
    def ad_max = mad_frac * taw
    def ad_pwp = -(1 - mad_frac) * taw
    # Soil moisture (%) at AD = 0
    def pct_at_ad_zero = (field_capacity - ad_max / max_root_zone_depth) * 100
    def target_in = target_ad_pct && target_ad_pct / 100.0 * ad_max

    # AD from a soil moisture reading, before clamping
    def ad_from_moisture(pct) = max_root_zone_depth * (pct - pct_at_ad_zero) / 100
    def pct_moisture(ad) = pct_at_ad_zero + ad / max_root_zone_depth * 100

    # AD at the start of the season: from initial_moisture_pct, or field capacity
    def initial_ad
      initial_moisture_pct ? ad_from_moisture(initial_moisture_pct).clamp(ad_pwp, ad_max) : ad_max
    end
  end

  # One day's resolved inputs. et0 nil = missing (gap-filled); rain and irrigation nil = none.
  # canopy is percent cover or LAI, matching Params#et_method.
  Day = Data.define(:date, :et0, :rain, :irrigation, :soil_moisture_pct, :canopy) do
    def initialize(date:, et0: nil, rain: nil, irrigation: nil, soil_moisture_pct: nil, canopy: 0.0)
      super
    end
  end

  # et_source: :computed, :gap_fill, or :missing (et0 missing and no recent ET to fill from;
  # the day then has no ET). moisture_reset: AD came from a soil moisture reading.
  Result = Data.define(:date, :adj_et, :et_source, :ad, :deep_drainage, :pct_moisture, :moisture_reset)

  module_function

  # Runs days in date order from initial_ad (default: the season-start value). et_history:
  # [[date, adj_et], ...] from before the first day, so a run that resumes mid-season (the
  # projection) gap-fills the same way.
  def run(params, days, initial_ad: params.initial_ad, et_history: [])
    ad = initial_ad
    history = et_history.dup
    days.map do |day|
      adj_et, et_source = crop_et(params, day, history)
      history << [day.date, adj_et] if et_source == :computed

      if day.soil_moisture_pct
        # A reading replaces the day's balance; that day's ET is reported but not applied
        raw = params.ad_from_moisture(day.soil_moisture_pct)
        drainage = [raw - params.ad_max, 0.0].max
        ad = raw.clamp(params.ad_pwp, params.ad_max)
      else
        water = ad + day.rain.to_f + day.irrigation.to_f - adj_et.to_f
        drainage = [water - params.ad_max, 0.0].max
        ad = water.clamp(params.ad_pwp, params.ad_max)
      end

      Result.new(date: day.date, adj_et: adj_et&.round(PRECISION), et_source:, ad: ad.round(PRECISION),
        deep_drainage: drainage.round(PRECISION), pct_moisture: params.pct_moisture(ad).round(PRECISION),
        moisture_reset: !day.soil_moisture_pct.nil?)
    end
  end

  def crop_et(params, day, history)
    return [CropEt.adjusted(params.et_method, day.et0, day.canopy), :computed] if day.et0

    recent = history.filter_map { |date, et| et if date >= day.date - GAP_FILL_DAYS }
    return [nil, :missing] if recent.empty?
    top = recent.max(GAP_FILL_TOP)
    [top.sum / top.size, :gap_fill]
  end

  # Today's status from AD (PLAN.md §5.5); projections add "caution" for a coming crossing
  def status(params, ad)
    if ad >= 0.9 * params.ad_max then :full
    elsif ad >= (params.target_in || 0.5 * params.ad_max) then :ok
    elsif ad > 0 then :caution
    else :irrigate
    end
  end
end

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
# - C21 (superseded by C22): the percent cover table scaled by the crop's Kc mid against FAO-56 ET0.
# - C22: crop ET by FAO-56's dual crop coefficient, (Kcb + Ke) × ET0, when Params has a crop: Kcb from
#   the canopy (CropEt.kcb), easing from mid season's to harvest's over the late season (Crop), and Ke
#   from the soil surface's wetting and drying (SoilEvaporation), carried from day to day.
module WaterBalance
  GAP_FILL_DAYS = 7 # gap fill: mean of the top GAP_FILL_TOP adjusted ETs in the previous 7 days
  GAP_FILL_TOP = 3
  PRECISION = 4

  # A planting's crop (C22): FAO-56 Table 17's basal coefficients at mid season and harvest
  # (plants.yml), its height in meters, and its season: the late stage's start (the day before its
  # canopy curve declines, Planting#late_stage_start; nil holds mid season's to the end) and its end.
  Crop = Data.define(:kcb_mid, :kcb_end, :height_m, :late_start, :end_date) do
    def initialize(kcb_mid:, kcb_end:, height_m:, late_start: nil, end_date: nil) = super

    def self.for(planting)
      plant = planting.plant
      plant&.kcb_mid && new(kcb_mid: plant.kcb_mid, kcb_end: plant.kcb_end, height_m: plant.crop_height_m,
        late_start: planting.late_stage_start, end_date: planting.end_date)
    end

    # Kcb at full cover on date, adjusted for the day's wind and humidity (FAO-56 eq. 70): mid
    # season's through late_start, then straight down to harvest's at end_date (eq. 66)
    def kcb_full(date, wind_mph: nil, rh_min_pct: nil)
      mid = CropEt.kc_mid(kcb_mid, height_m, wind_mph:, rh_min_pct:)
      return mid unless late_start && end_date && date > late_start && end_date > late_start
      last = (kcb_end >= CropEt::KCB_END_ADJUST_FROM) ? CropEt.kc_mid(kcb_end, height_m, wind_mph:, rh_min_pct:) : kcb_end
      mid + (last - mid) * [(date - late_start).to_f / (end_date - late_start), 1.0].min
    end
  end

  # FC and PWP are fractions; MRZD inches; MAD a fraction; percents are 0–100. crop: a Crop, or nil
  # for the percent cover table as legacy used it (CropEt). rew: the soil's readily evaporable water
  # (inches; nil: SoilEvaporation's default) and irrigation_fw the fraction of the surface its
  # irrigation wets, for soil evaporation (C22).
  Params = Data.define(:field_capacity, :perm_wilting_pt, :max_root_zone_depth, :mad_frac, :et_method,
    :target_ad_pct, :initial_moisture_pct, :crop, :rew, :irrigation_fw) do
    def initialize(field_capacity:, perm_wilting_pt:, max_root_zone_depth:, mad_frac:, et_method: "pct_cover",
      target_ad_pct: nil, initial_moisture_pct: nil, crop: nil, rew: nil, irrigation_fw: 1.0)
      unless perm_wilting_pt.positive? && perm_wilting_pt < field_capacity && field_capacity < 1
        raise ArgumentError, "need 0 < wilting point < field capacity < 1"
      end
      raise ArgumentError, "root zone depth must be positive" unless max_root_zone_depth.positive?
      raise ArgumentError, "MAD must be between 0 and 1" unless mad_frac.positive? && mad_frac < 1
      super
    end

    # The planting's own soil values (its season's, PLAN.md Phase 8 G.9)
    def self.for(planting)
      new(field_capacity: planting.effective_field_capacity, perm_wilting_pt: planting.effective_perm_wilting_pt,
        max_root_zone_depth: planting.max_root_zone_depth, mad_frac: planting.mad_frac,
        et_method: planting.et_method, target_ad_pct: planting.target_ad_pct,
        initial_moisture_pct: planting.initial_moisture_pct, crop: Crop.for(planting),
        rew: planting.soil_type.rew_in, irrigation_fw: SoilEvaporation.wetted_fraction(planting.system&.kind))
    end

    # The soil surface's evaporation layer (C22), from the planting's own soil values
    def evaporation = SoilEvaporation.new(tew: SoilEvaporation.tew(field_capacity, perm_wilting_pt), rew:)

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
  # canopy is percent cover or LAI, matching Params#et_method. wind_mph (mean at 10 m) and
  # rh_min_pct adjust the crop's coefficients (CropEt.kc_mid); nil counts as FAO-56's standard climate.
  Day = Data.define(:date, :et0, :rain, :irrigation, :soil_moisture_pct, :canopy, :wind_mph, :rh_min_pct) do
    def initialize(date:, et0: nil, rain: nil, irrigation: nil, soil_moisture_pct: nil, canopy: 0.0, wind_mph: nil,
      rh_min_pct: nil)
      super
    end
  end

  # et_source: :computed, :gap_fill, or :missing (et0 missing and no recent ET to fill from;
  # the day then has no ET). moisture_reset: AD came from a soil moisture reading. evaporation: the
  # soil surface's SoilEvaporation::State at the end of the day (nil without a crop), for a run
  # resuming from it.
  Result = Data.define(:date, :adj_et, :et_source, :ad, :deep_drainage, :pct_moisture, :moisture_reset,
    :evaporation) do
    def initialize(evaporation: nil, **) = super
  end

  module_function

  # Runs days in date order from initial_ad (default: the season-start value). et_history:
  # [[date, adj_et], ...] from before the first day, so a run that resumes mid-season (the
  # projection) gap-fills the same way; evaporation: the soil surface's state it resumes from
  # (Result#evaporation; default: wet, as at season start).
  def run(params, days, initial_ad: params.initial_ad, et_history: [], evaporation: nil)
    ad = initial_ad
    history = et_history.dup
    layer = params.crop && params.evaporation
    surface = layer && (evaporation || SoilEvaporation::State.initial)
    days.map do |day|
      adj_et, et_source, after = crop_et(params, day, history, layer, surface)
      history << [day.date, adj_et] if et_source == :computed

      if day.soil_moisture_pct
        # A reading replaces the day's balance; that day's ET is reported but not applied, and the
        # surface layer is left as it was
        raw = params.ad_from_moisture(day.soil_moisture_pct)
        drainage = [raw - params.ad_max, 0.0].max
        ad = raw.clamp(params.ad_pwp, params.ad_max)
      else
        water = ad + day.rain.to_f + day.irrigation.to_f - adj_et.to_f
        drainage = [water - params.ad_max, 0.0].max
        ad = water.clamp(params.ad_pwp, params.ad_max)
        surface = after if after
      end

      Result.new(date: day.date, adj_et: adj_et&.round(PRECISION), et_source:, ad: ad.round(PRECISION),
        deep_drainage: drainage.round(PRECISION), pct_moisture: params.pct_moisture(ad).round(PRECISION),
        moisture_reset: !day.soil_moisture_pct.nil?, evaporation: surface)
    end
  end

  # [adj_et, source, the surface layer after the day (nil unless computed with a crop)]
  def crop_et(params, day, history, layer = nil, surface = nil)
    if day.et0
      return [CropEt.adjusted(params.et_method, day.et0, day.canopy), :computed, nil] unless layer
      adj_et, after = dual(params, day, layer, surface)
      return [adj_et, :computed, after]
    end

    recent = history.filter_map { |date, et| et if date >= day.date - GAP_FILL_DAYS }
    return [nil, :missing, nil] if recent.empty?
    top = recent.max(GAP_FILL_TOP)
    [top.sum / top.size, :gap_fill, nil]
  end

  # FAO-56's dual crop coefficient (C22): [crop ET, the surface layer after the day]
  def dual(params, day, layer, surface)
    crop = params.crop
    et0 = [day.et0, 0.0].max
    weather = {wind_mph: day.wind_mph, rh_min_pct: day.rh_min_pct}
    kcb = CropEt.kcb(params.et_method, crop.kcb_full(day.date, **weather), day.canopy, crop.height_m)
    step = layer.step(surface, et0:, kcb:, kc_max: CropEt.kc_max(kcb, crop.height_m, **weather),
      cover: CropEt.cover_fraction(params.et_method, day.canopy), rain: day.rain, irrigation: day.irrigation,
      irrigation_fw: params.irrigation_fw)
    [(kcb + step.ke) * et0, step.state]
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

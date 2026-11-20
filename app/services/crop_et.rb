# Crop (adjusted) ET from reference ET (et0, in/day) and the canopy, by percent cover or LAI.
# Ported from legacy ETCalculator with fixes C8 (PLAN.md §5.4).
#
# C21 (PLAN.md §9, Q11): the percent cover table was fitted to AgWeather's ET, which ran about 1.1–1.2
# times FAO-56 grass reference ET, so its "full cover = reference ET" meant a crop coefficient near
# FAO-56's mid-season values. Against WISP's corrected FAO-56 ET0 (D12) the table is scaled by a factor
# rising with cover, from 1 on bare soil to the crop's Kc mid at 80% cover and above, and the LAI
# formula tops out at the crop's Kc mid in place of 1.1. Kc mid is FAO-56 Table 12's
# (db/reference/plants.yml), adjusted for the day's wind and humidity (eq. 62, kc_mid). kc: nil keeps
# the table as it was (legacy).
#
# C22 (PLAN.md §9): for a planting with a crop, FAO-56's dual crop coefficient (chapter 7) replaces
# the table: crop ET = (Kcb + Ke) × ET0, Kcb the basal coefficient (transpiration, with the surface
# dry) from the canopy (basal), Ke soil evaporation (SoilEvaporation, run day by day in
# WaterBalance). The table stays for a planting without a crop's coefficients, and in LegacyEngine.
module CropEt
  # Linear regressions of adjusted ET on reference ET at 10% cover steps (J. Panuska, from
  # Table C of UW Extension A3600, "Irrigation Management in Wisconsin"): [intercept, slope]
  # for 10%, 20%, ... 80% cover. At 80% cover and above, adjusted ET = et0.
  PCT_COVER_COEFFICIENTS = [
    [-0.002263, 0.2377],
    [-0.002789, 0.3956],
    [-0.002368, 0.5395],
    [-0.000316, 0.6684],
    [-0.000053, 0.7781],
    [0.001053, 0.8772],
    [0.001947, 0.9395],
    [0.0, 1.0]
  ].freeze

  # Bare-soil (0% cover) evaporation steps by et0: [upper bound (exclusive), in/day].
  # Legacy used closed ranges (0..0.159, 0.160..0.319), so e.g. 0.1595 fell to the top step.
  BARE_SOIL_STEPS = [[0.16, 0.0], [0.32, 0.01]].freeze
  BARE_SOIL_MAX = 0.02

  # LAI to crop coefficient (WIS v6.3.11): Kc = 1.1 × (1 − e^(−1.5·LAI))
  LAI_KC_MAX = 1.1
  LAI_EXTINCTION = 1.5

  # Cover at and above which the table's crop ET is reference ET (Kc mid with C21)
  FULL_COVER = 80.0

  # FAO-56 eq. 62's standard climate and validity ranges: wind at 2 m (m/s), minimum RH (%), height (m)
  STANDARD_WIND_2M = 2.0
  STANDARD_RH_MIN = 45.0
  WIND_2M_RANGE = (1.0..6.0)
  RH_MIN_RANGE = (20.0..80.0)
  MIN_HEIGHT_M = 0.1
  MPH_TO_MS = 0.44704

  # FAO-56 eqs. 97–98 (C22): the basal coefficient of bare soil under a sparse canopy (Kc min), the
  # multiplier on cover for its effective shade (ML), Kc max's base (eq. 72), and LAI's extinction
  # coefficient for cover from leaf area (fc = 1 − e^(−0.7·LAI))
  KC_MIN = 0.15
  ML = 2.0
  KC_MAX = 1.2
  LAI_COVER_EXTINCTION = 0.7
  # Eq. 70 adjusts a late-season Kcb only from this value up
  KCB_END_ADJUST_FROM = 0.45

  module_function

  # kc: the day's crop coefficient at full cover (kc_mid), or nil for the table as it was
  def adjusted(et_method, et0, canopy, kc: nil)
    case et_method
    when "pct_cover" then from_pct_cover(et0, canopy, kc:)
    when "lai" then from_lai(et0, canopy, kc:)
    else raise ArgumentError, "unknown ET method #{et_method.inspect}"
    end
  end

  # FAO-56 eq. 62 (eq. 70 for Kcb, eq. 72 for Kc max's 1.2: the same adjustment): Table 12's Kc mid for a day's wind (mean at 10 m, mph, as stored) and minimum
  # relative humidity (%), each clamped to the equation's range; a missing one counts as the table's
  # standard (2 m/s, 45%). Not applied below 0.1 m, where a crop behaves like the grass reference.
  def kc_mid(kc, height_m, wind_mph: nil, rh_min_pct: nil)
    return kc unless height_m && height_m >= MIN_HEIGHT_M
    u2 = wind_mph ? Weather::Fao56.wind_speed_2m(wind_mph * MPH_TO_MS).clamp(WIND_2M_RANGE) : STANDARD_WIND_2M
    rh_min = rh_min_pct ? rh_min_pct.to_f.clamp(RH_MIN_RANGE) : STANDARD_RH_MIN
    kc + (0.04 * (u2 - STANDARD_WIND_2M) - 0.004 * (rh_min - STANDARD_RH_MIN)) * (height_m / 3)**0.3
  end

  # FAO-56 eq. 98: Kcb for percent cover, from kcb_full (the crop's Kcb at full cover that day,
  # WaterBalance::Crop#kcb_full) and its height (m). The crop is as tall as it covers (h = height ×
  # fc). No cover is bare soil: Kcb 0, its ET all evaporation (Ke).
  def kcb_from_cover(kcb_full, pct_cover, height_m)
    fc = pct_cover.to_f.clamp(0.0, 100.0) / 100
    return 0.0 if fc.zero?
    kd = [1.0, ML * fc, fc**(1 / (1 + height_m * fc))].min
    KC_MIN + kd * (kcb_full - KC_MIN)
  end

  # FAO-56 eq. 97: Kcb from leaf area index
  def kcb_from_lai(kcb_full, lai)
    lai = [lai.to_f, 0.0].max
    return 0.0 if lai.zero?
    KC_MIN + (kcb_full - KC_MIN) * (1 - Math.exp(-LAI_COVER_EXTINCTION * lai))
  end

  # The canopy's fraction of the ground (fc, for evaporation's exposed share): percent cover, or for
  # LAI the same exponential as eq. 97's
  def cover_fraction(et_method, canopy)
    case et_method
    when "pct_cover" then canopy.to_f.clamp(0.0, 100.0) / 100
    when "lai" then 1 - Math.exp(-LAI_COVER_EXTINCTION * [canopy.to_f, 0.0].max)
    else raise ArgumentError, "unknown ET method #{et_method.inspect}"
    end
  end

  # Kcb for the canopy, percent cover or LAI by et_method
  def kcb(et_method, kcb_full, canopy, height_m)
    (et_method == "lai") ? kcb_from_lai(kcb_full, canopy) : kcb_from_cover(kcb_full, canopy, height_m)
  end

  # FAO-56 eq. 72: the most the crop and wet soil can use together, for the day's wind and humidity
  def kc_max(kcb, height_m, wind_mph: nil, rh_min_pct: nil)
    [kc_mid(KC_MAX, height_m, wind_mph:, rh_min_pct:), kcb + 0.05].max
  end

  def from_pct_cover(et0, pct_cover, kc: nil)
    table = table_et(et0, pct_cover)
    return table unless kc
    cover = [pct_cover.to_f.clamp(0.0, 100.0), FULL_COVER].min
    table * (1 + (kc - 1) * cover / FULL_COVER)
  end

  # A3600 Table C, interpolated between its 10% steps (legacy, with C8's fixes)
  def table_et(et0, pct_cover)
    return 0.0 unless et0.positive?
    cover = pct_cover.to_f.clamp(0.0, 100.0) # legacy treated negative cover as full cover
    return et0 if cover >= 80

    step = (cover / 10).floor
    low = (step == 0) ? bare_soil(et0) : regression(step, et0)
    high = regression(step + 1, et0)
    adjusted = low + (cover - step * 10) / 10 * (high - low)
    [adjusted, 0.0].max # the 10% regression goes negative below et0 ≈ 0.0095
  end

  def from_lai(et0, lai, kc: nil)
    return 0.0 unless et0.positive?
    et0 * kc_from_lai(lai, kc || LAI_KC_MAX)
  end

  def kc_from_lai(lai, kc_max = LAI_KC_MAX)
    kc_max * (1 - Math.exp(-LAI_EXTINCTION * [lai.to_f, 0.0].max))
  end

  def bare_soil(et0)
    BARE_SOIL_STEPS.find { |upper, _| et0 < upper }&.last || BARE_SOIL_MAX
  end

  def regression(pct_step, et0)
    intercept, slope = PCT_COVER_COEFFICIENTS.fetch(pct_step - 1)
    intercept + et0 * slope
  end
end

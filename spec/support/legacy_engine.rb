# The legacy WISP water balance, condensed from ../wisp but behaving the same:
# ETCalculator#adj_et_pct_cover / #adj_et_lai_for_nonclumping, FieldDailyWeather#old_update_balances,
# Field#do_balances and RingBuffer#mean_top_3. Missing reference ET is 0.0, as legacy stored it.
#
# Each fix in docs/legacy-audit.md that changes the balance can be switched on. With every fix on it must match
# WaterBalance, and without them every differing day must trace to a fix
# (spec/services/legacy_engine_spec.rb). It was checked against 30 legacy production fields
# while it was built (golden tests, since retired). C3/C4 change the canopy series rather
# than the balance, so callers pass the canopy they want.
module LegacyEngine
  FIXES = {
    c2: "moisture reading capped at AD_max (not TAW) and floored at the wilting point",
    c7: "gap fill from computed days only, within the previous 7 days",
    c8: "percent-cover ET: half-open bare-soil steps, cover clamped to 0–100, never negative",
    c19: "ET recomputed on soil moisture reading days (legacy kept a stale stored value, which fed gap fill)",
    c21: "crop ET by the crop's FAO-56 Kc mid (adjusted for wind and humidity) against FAO-56 ET0: the percent " \
      "cover table scaled from 1 on bare soil to Kc mid at 80% cover, and LAI's maximum Kc (legacy: the table as " \
      "is, against AgWeather's ET, and 1.1)",
    c22: "crop ET by FAO-56's dual crop coefficient: a basal Kcb from the canopy (eqs. 97–98), easing to Kcb end over " \
      "the late season, plus soil evaporation Ke from the surface layer's wetting and drying (eqs. 71–77), in place " \
      "of the percent cover table (legacy: the table, whose bare soil evaporates 0–0.02 in a day)",
    c26: "with C22, water stress below the MAD trigger: Kcb scaled by FAO-56's Ks (eq. 84), 1 at AD 0 down to 0 at " \
      "the wilting point, from the day's starting AD (legacy: full crop ET however dry the soil)"
  }.freeze

  # Fixes that change the canopy series rather than the balance
  CANOPY_FIXES = {
    c3: "percent cover held to the end date (legacy: 6 days) and interpolated from emergence",
    c4: "LAI growth curve for field corn only (legacy used the corn curve for every crop)",
    c20: "crop canopy curves: followed with no readings and between readings (legacy: 0% cover until the first " \
      "reading, then straight lines)",
    c23: "percent cover curves run by growing degree days at the planting's weather cell (stored weather, the " \
      "forecast, then normals), not calendar days since emergence"
  }.freeze

  module_function

  # days: [{date:, et0:, rain:, irrigation:, moisture:, canopy:, stored_adj_et:}]; returns AD per
  # day. stored_adj_et is the adj_et legacy had saved for the day, which it kept on reading days.
  # With C21, kc_mid and crop_height_m (FAO-56 Table 12) and each day's :wind_mph and :rh_min_pct.
  # With C22, kcb_mid and kcb_end (Table 17), late_start and end_date (the late season), rew (inches)
  # and irrigation_fw.
  def run(field_capacity:, perm_wilting_pt:, max_root_zone_depth:, mad_frac:, days:, et_method: "pct_cover", fixes: [],
    initial_ad: nil, kc_mid: nil, crop_height_m: nil, kcb_mid: nil, kcb_end: nil, late_start: nil, end_date: nil,
    rew: nil, irrigation_fw: 1.0)
    mrzd = max_root_zone_depth
    taw = (field_capacity - perm_wilting_pt) * mrzd
    ad_max = mad_frac * taw
    ad_pwp = -1 * (1.0 - mad_frac) * taw
    pct_at_ad_min = (field_capacity - ad_max / mrzd) * 100
    ad = initial_ad || [mrzd * (field_capacity * 100 - pct_at_ad_min) / 100, taw].min
    ring = [] # last 7 adj_ets, filled ones included unless C7
    computed = [] # [date, adj_et] for C7
    dual = kcb_mid && fixes.include?(:c22)
    tew = (field_capacity - perm_wilting_pt / 2) * 3.937007874 # FAO-56 eq. 73, Ze 0.1 m
    rew = [rew || 9 / 25.4, tew].min
    de, fw = 0.0, 1.0 # surface layer depletion, the last wetting's fraction wetted

    days.map do |day|
      ref_et = day[:et0] || 0.0
      kc = kc_mid && fixes.include?(:c21) && fao56_kc_mid(kc_mid, crop_height_m, day[:wind_mph], day[:rh_min_pct])
      if dual
        ks = (fixes.include?(:c26) && ad < 0) ? [1 - ad / ad_pwp, 0.0].max : 1.0
        adj_et, new_de, new_fw = dual_et(ref_et, day, et_method:, height: crop_height_m, de:, fw:, tew:, rew:, irrigation_fw:,
          kcb: late_kcb(kcb_mid, kcb_end, crop_height_m, late_start, end_date, day), ks:)
      end
      adj_et ||= if et_method == "lai"
        lai_et(ref_et, day[:canopy], kc || 1.1)
      else
        pct_cover_et(ref_et, day[:canopy], fixes.include?(:c8)) * (kc ? 1 + (kc - 1) * [day[:canopy].to_f.clamp(0, 100), 80].min / 80 : 1)
      end
      filled = ref_et < 0.00001
      if day[:moisture] && day.key?(:stored_adj_et) && !fixes.include?(:c19)
        adj_et = day[:stored_adj_et] || 0.0
        filled = false
      elsif filled
        adj_et = if fixes.include?(:c7)
          recent = computed.filter_map { |date, et| et if date >= day[:date] - 7 }
          recent.empty? ? 0.0 : recent.max(3).sum / recent.max(3).size
        else
          top = ring.last(7).sort.reverse[0...3]
          top.empty? ? 0.0 : top.sum / top.length
        end
      end
      computed << [day[:date], adj_et] unless filled
      de, fw = new_de, new_fw if dual && !filled && !day[:moisture]

      if day[:moisture]
        raw = mrzd * (day[:moisture] - pct_at_ad_min) / 100
        ad = fixes.include?(:c2) ? raw.clamp(ad_pwp, ad_max) : [raw, taw].min
      else
        water = ad + (day[:rain] || 0.0) + (day[:irrigation] || 0.0) - adj_et
        ad = (water - ad_max > 0.00001) ? ad_max : water
        ad = [ad, ad_pwp].max
      end
      ring << adj_et unless filled && fixes.include?(:c7)
      ad
    end
  end

  def pct_cover_et(ref_et, pct_cover, fixed)
    pct_cover ||= 0.0
    pct_cover = pct_cover.clamp(0.0, 100.0) if fixed
    return 0.0 if ref_et < 0.000001
    coeff = [[0, 0], [-0.002263, 0.2377], [-0.002789, 0.3956], [-0.002368, 0.5395], [-0.000316, 0.6684],
      [-0.000053, 0.7781], [0.001053, 0.8772], [0.001947, 0.9395], [0.000000, 1.000]]
    index = (pct_cover / 10).floor
    adj_et = case index
    when 0
      low = if fixed
        if ref_et < 0.16
          0.0
        else
          ((ref_et < 0.32) ? 0.010 : 0.020)
        end
      else
        case ref_et
        when 0..0.159 then 0.0
        when 0.160..0.319 then 0.010
        else 0.020
        end
      end
      high = coeff[1][0] + ref_et * coeff[1][1]
      low + ((pct_cover / 10) * (high - low))
    when 1..7
      low = coeff[index][0] + ref_et * coeff[index][1]
      high = coeff[index + 1][0] + ref_et * coeff[index + 1][1]
      low + (((pct_cover - index * 10) / 10) * (high - low))
    else
      ref_et
    end
    fixed ? [adj_et, 0.0].max : adj_et
  end

  def lai_et(ref_et, lai, kc_max = 1.1)
    ref_et * kc_max * (1 - Math.exp(-1.5 * (lai || 0.0)))
  end

  # C22: Kcb at full cover on the day, from Kcb mid to Kcb end (unadjusted below 0.45) after late_start
  def late_kcb(kcb_mid, kcb_end, height, late_start, end_date, day)
    mid = fao56_kc_mid(kcb_mid, height, day[:wind_mph], day[:rh_min_pct])
    return mid unless late_start && end_date && end_date > late_start && day[:date] > late_start
    last = (kcb_end < 0.45) ? kcb_end : fao56_kc_mid(kcb_end, height, day[:wind_mph], day[:rh_min_pct])
    share = [(day[:date] - late_start).to_f / (end_date - late_start), 1.0].min
    mid * (1 - share) + last * share
  end

  # C22: [crop ET, De, fw] for one day: FAO-56 eqs. 97–98 for Kcb, 71–77 for Ke; with C26, Kcb × ks
  def dual_et(ref_et, day, et_method:, height:, kcb:, de:, fw:, tew:, rew:, irrigation_fw:, ks: 1.0)
    canopy = [day[:canopy] || 0.0, 0.0].max
    if et_method == "lai"
      fc = 1 - Math.exp(-0.7 * canopy)
      basal = canopy.zero? ? 0.0 : 0.15 + (kcb - 0.15) * fc
    else
      fc = [canopy, 100.0].min / 100
      kd = [1.0, 2 * fc, fc**(1.0 / (1 + height * fc))].min
      basal = fc.zero? ? 0.0 : 0.15 + kd * (kcb - 0.15)
    end
    kc_max = [fao56_kc_mid(1.2, height, day[:wind_mph], day[:rh_min_pct]), basal + 0.05].max
    kr = (de > rew) ? [(tew - de) / (tew - rew), 0.0].max : 1.0
    rain, irrigation = day[:rain] || 0.0, day[:irrigation] || 0.0
    fw = 1.0 if rain >= 0.1
    fw = irrigation_fw if rain < 0.1 && irrigation > 0
    de = [de - rain - irrigation / fw, 0.0].max
    few = [1 - fc, fw].min.clamp(0.01, 1.0)
    ke = [kr * (kc_max - basal), few * kc_max].min
    de = (de + ke * ref_et / few).clamp(0.0, tew)
    [(ks * basal + ke) * ref_et, de, fw]
  end

  # FAO-56 eq. 62, written out independently of CropEt.kc_mid
  def fao56_kc_mid(kc, height, wind_mph, rh_min)
    u2 = wind_mph ? (wind_mph * 0.44704 * 4.87 / Math.log(672.58)).clamp(1.0, 6.0) : 2.0
    rh = rh_min ? rh_min.clamp(20.0, 80.0) : 45.0
    kc + (0.04 * (u2 - 2) - 0.004 * (rh - 45)) * (height / 3.0)**0.3
  end
end

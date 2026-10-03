# The legacy WISP water balance, condensed from ../wisp but behaving the same:
# ETCalculator#adj_et_pct_cover / #adj_et_lai_for_nonclumping, FieldDailyWeather#old_update_balances,
# Field#do_balances and RingBuffer#mean_top_3. Missing reference ET is 0.0, as legacy stored it.
#
# Each PLAN.md §9 fix that changes the balance can be switched on, so a difference between
# WaterBalance and legacy can be traced to the fixes that cause it (spec/golden). With every fix
# on, it must match WaterBalance (spec/services/legacy_engine_spec.rb). C3 (canopy held to the end
# date) changes the canopy series, not the balance, so callers pass the canopy they want.
module LegacyEngine
  FIXES = {
    c2: "moisture reading capped at AD_max (not TAW) and floored at the wilting point",
    c7: "gap fill from computed days only, within the previous 7 days",
    c8: "percent-cover ET: half-open bare-soil steps, cover clamped to 0–100, never negative",
    c19: "ET recomputed on soil moisture reading days (legacy kept a stale stored value, which fed gap fill)"
  }.freeze

  # Fixes that change the canopy series rather than the balance; the golden tests check them by
  # running with legacy's own canopy
  CANOPY_FIXES = {
    c3: "percent cover held to the end date (legacy: 6 days) and interpolated from emergence",
    c4: "LAI growth curve for field corn only (legacy used the corn curve for every crop)"
  }.freeze

  module_function

  # days: [{date:, et0:, rain:, irrigation:, moisture:, canopy:, stored_adj_et:}]; returns AD per
  # day. stored_adj_et is the adj_et legacy had saved for the day, which it kept on reading days.
  def run(field_capacity:, perm_wilting_pt:, max_root_zone_depth:, mad_frac:, days:, et_method: "pct_cover", fixes: [],
    initial_ad: nil)
    mrzd = max_root_zone_depth
    taw = (field_capacity - perm_wilting_pt) * mrzd
    ad_max = mad_frac * taw
    ad_pwp = -1 * (1.0 - mad_frac) * taw
    pct_at_ad_min = (field_capacity - ad_max / mrzd) * 100
    ad = initial_ad || [mrzd * (field_capacity * 100 - pct_at_ad_min) / 100, taw].min
    ring = [] # last 7 adj_ets, filled ones included unless C7
    computed = [] # [date, adj_et] for C7

    days.map do |day|
      ref_et = day[:et0] || 0.0
      adj_et = (et_method == "lai") ? lai_et(ref_et, day[:canopy]) : pct_cover_et(ref_et, day[:canopy], fixes.include?(:c8))
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

  def lai_et(ref_et, lai)
    ref_et * 1.1 * (1 - Math.exp(-1.5 * (lai || 0.0)))
  end
end

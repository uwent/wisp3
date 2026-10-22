module Weather
  # Growing degree days, by the standard corn method (modified GDD): daily max and min capped at
  # 86 °F and floored at 50 °F, then their mean minus 50. Groundwork for GDD-driven canopy
  # curves (PLAN.md Q2 option C), and shown to growers.
  module DegreeDays
    BASE_F = 50.0
    CAP_F = 86.0

    module_function

    def daily(tmax_f, tmin_f, base: BASE_F, cap: CAP_F)
      return if tmax_f.nil? || tmin_f.nil?
      high = tmax_f.clamp(base, cap)
      low = tmin_f.clamp(base, cap)
      (high + low) / 2 - base
    end
  end
end

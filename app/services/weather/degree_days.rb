module Weather
  # Growing degree days.
  #
  # daily: the standard corn method shown to growers (modified GDD, °F): daily max and min capped
  # at 86 °F and floored at 50 °F, then their mean minus 50.
  #
  # aquacrop: thermal time for canopy curves (ThermalTime, PLAN.md §9 C23), in °C days, by FAO
  # AquaCrop's method 3, the one AquaCrop-OSPy's crop files use (GDDmethod 3,
  # aquacrop/solution/growing_degree_day.py; AquaCrop reference manual, ch. 3, "Growing degree
  # days"): the max is held between the crop's base and upper temperatures, the min only below the
  # upper, and their mean, less the base, is at least 0. A cold night under a warm day still counts
  # the day's warmth less the night's chill, where clamping both (method 2) would count it as no
  # colder than the base.
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

    # °C days from a day's max and min in °F, for a crop's base and upper temperatures in °C
    def aquacrop(tmax_f, tmin_f, base_c:, upper_c:)
      return if tmax_f.nil? || tmin_f.nil?
      high = ((tmax_f - 32) * 5 / 9.0).clamp(base_c, upper_c)
      low = [(tmin_f - 32) * 5 / 9.0, upper_c].min
      [(high + low) / 2 - base_c, 0.0].max
    end
  end
end

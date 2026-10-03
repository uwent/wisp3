# Crop (adjusted) ET from reference ET (et0, in/day) and the canopy, by percent cover or LAI.
# Ported from legacy ETCalculator with fixes C8 (PLAN.md §5.4).
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

  module_function

  def adjusted(et_method, et0, canopy)
    case et_method
    when "pct_cover" then from_pct_cover(et0, canopy)
    when "lai" then from_lai(et0, canopy)
    else raise ArgumentError, "unknown ET method #{et_method.inspect}"
    end
  end

  def from_pct_cover(et0, pct_cover)
    return 0.0 unless et0.positive?
    cover = pct_cover.to_f.clamp(0.0, 100.0) # legacy treated negative cover as full cover
    return et0 if cover >= 80

    step = (cover / 10).floor
    low = (step == 0) ? bare_soil(et0) : regression(step, et0)
    high = regression(step + 1, et0)
    adjusted = low + (cover - step * 10) / 10 * (high - low)
    [adjusted, 0.0].max # the 10% regression goes negative below et0 ≈ 0.0095
  end

  def from_lai(et0, lai)
    return 0.0 unless et0.positive?
    et0 * kc_from_lai(lai)
  end

  def kc_from_lai(lai)
    LAI_KC_MAX * (1 - Math.exp(-LAI_EXTINCTION * [lai.to_f, 0.0].max))
  end

  def bare_soil(et0)
    BARE_SOIL_STEPS.find { |upper, _| et0 < upper }&.last || BARE_SOIL_MAX
  end

  def regression(pct_step, et0)
    intercept, slope = PCT_COVER_COEFFICIENTS.fetch(pct_step - 1)
    intercept + et0 * slope
  end
end

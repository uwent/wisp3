# Evaporation from the soil surface (PLAN.md §9 C22): FAO-56 chapter 7's evaporation coefficient Ke
# (eqs. 71–77, Allen et al. 1998, https://www.fao.org/4/x0490e/x0490e0c.htm), the half of the dual
# crop coefficient that CropEt's basal coefficient Kcb leaves out. Plain Ruby; depths in inches.
#
# The surface layer (Ze = 0.10 m) holds TEW (total evaporable water, eq. 73) above air dry. Its
# depletion De rises as it evaporates and falls with rain and irrigation. While De is within REW
# (readily evaporable water, FAO-56 Table 19) evaporation runs at the energy available (Kr = 1);
# beyond it, it slows in proportion to the water left (Kr = (TEW − De) / (TEW − REW), eq. 74).
#
#   Ke  = min(Kr × (Kc max − Kcb), few × Kc max)                               (eq. 71)
#   few = min(1 − fc, fw), within 0.01–1                                        (eq. 75)
#   De  = De(yesterday) − rain − irrigation / fw + Ke × ET0 / few, within 0–TEW (eq. 77)
#
# Kr comes from yesterday's De, before the day's wetting (eq. 74's De,i−1). fw is the fraction of the
# surface wetted: 1 for rain of WETTING_RAIN_IN or more; for irrigation alone, the system's
# (wetted_fraction); otherwise the last wetting's. Runoff, transpiration from the layer and its deep
# percolation (eq. 77's RO, Tew and DPe) are left out, as FAO-56 allows for coarse soils.
class SoilEvaporation
  # FAO-56 eq. 73's surface layer, 0.10 m, in inches
  SURFACE_LAYER_IN = 0.10 / 0.0254
  # REW when a soil type has none: loam's (Table 19, 8–10 mm), 9 mm
  DEFAULT_REW_IN = 9.0 / 25.4
  # Rain from which the whole surface counts as wetted (FAO-56 suggests about 3–4 mm)
  WETTING_RAIN_IN = 0.1
  # FAO-56 Table 20, by irrigation system kind (Pivot::KINDS): trickle 0.3–0.4; sprinklers 1.0. A
  # location (point) is taken as sprinklers.
  WETTED_FRACTIONS = {"drip" => 0.35}.freeze
  FEW_RANGE = (0.01..1.0)

  # depletion: De at the end of the day (inches); fw: the last wetting's fraction of the surface
  State = Data.define(:depletion, :fw) do
    def self.initial = new(depletion: 0.0, fw: 1.0)
  end

  # ke: the day's evaporation coefficient; state: the layer at the end of the day
  Step = Data.define(:ke, :state)

  attr_reader :tew, :rew

  # FAO-56 eq. 73, from volumetric fractions
  def self.tew(field_capacity, perm_wilting_pt) = (field_capacity - 0.5 * perm_wilting_pt) * SURFACE_LAYER_IN

  def self.wetted_fraction(kind) = WETTED_FRACTIONS.fetch(kind, 1.0)

  # rew is capped at tew
  def initialize(tew:, rew: DEFAULT_REW_IN)
    raise ArgumentError, "TEW must be positive" unless tew.positive?
    @tew, @rew = tew, [rew || DEFAULT_REW_IN, tew].min
  end

  # One day. kcb and kc_max: the day's basal and maximum coefficients; cover: the canopy's fraction
  # of the ground (fc); rain and irrigation in inches (nil: none); irrigation_fw: the irrigation
  # system's wetted fraction.
  def step(state, et0:, kcb:, kc_max:, cover:, rain: nil, irrigation: nil, irrigation_fw: 1.0)
    kr = (state.depletion <= rew) ? 1.0 : ((tew - state.depletion) / (tew - rew)).clamp(0.0, 1.0)
    rain, irrigation = rain.to_f, irrigation.to_f
    fw = if rain >= WETTING_RAIN_IN then 1.0
    elsif irrigation.positive? then irrigation_fw
    else state.fw
    end
    depletion = [state.depletion - rain - irrigation / fw, 0.0].max
    few = [1 - cover, fw].min.clamp(FEW_RANGE)
    ke = [kr * (kc_max - kcb), few * kc_max].min
    depletion = (depletion + ke * et0 / few).clamp(0.0, tew)
    Step.new(ke:, state: State.new(depletion:, fw:))
  end
end

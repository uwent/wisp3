# LAI growth curves by days since emergence, for plantings on the LAI method (only crops with one
# can use it); Canopy combines them with entered readings. Only field corn has one (PLAN.md §5.3,
# Q2); legacy applied it to every crop (C4) and gave sweet corn a placeholder that produced negative
# ET (C18).
module CanopyModel
  # Raise when a curve changes, so fits to it are redone (CanopyFit.fetch)
  VERSION = 1

  CURVES = {
    # WI_Irrigation_Scheduler_(WIS)_VV6.3.11.xls: peaks at LAI 4.07 on day 80
    "field_corn" => ->(days) { 9e-12 * days**7.95 * Math.exp(-0.1 * days) }
  }.freeze

  # LAI on a day, or nil if there's no curve for the key. Fitted to readings (CanopyFit), the curve can
  # run shift days later, grow stretch times slower and reach height times its LAI.
  def self.lai(key, days_since_emergence, shift: 0, stretch: 1.0, height: 1.0)
    curve = CURVES[key] or return
    return 0.0 if days_since_emergence.negative?
    days = (days_since_emergence - shift) / stretch.to_f
    days.negative? ? 0.0 : curve.call(days) * height
  end

  # The curve as a function of date for a crop that emerged on emergence_date (Canopy), or nil
  def self.from(key, emergence_date, **fit)
    ->(date) { lai(key, (date - emergence_date).to_i, **fit) } if CURVES.key?(key)
  end
end

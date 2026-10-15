# LAI growth curves by days since emergence, for plantings on the LAI method (only crops with one
# can use it); Canopy combines them with entered readings. Only field corn has one (PLAN.md §5.3,
# Q2); legacy applied it to every crop (C4) and gave sweet corn a placeholder that produced negative
# ET (C18).
module CanopyModel
  CURVES = {
    # WI_Irrigation_Scheduler_(WIS)_VV6.3.11.xls: peaks at LAI 4.07 on day 80
    "field_corn" => ->(days) { 9e-12 * days**7.95 * Math.exp(-0.1 * days) }
  }.freeze

  # LAI on a day, or nil if there's no curve for the key
  def self.lai(key, days_since_emergence)
    curve = CURVES[key] or return
    days_since_emergence.negative? ? 0.0 : curve.call(days_since_emergence)
  end

  # The curve as a function of date for a crop that emerged on emergence_date (Canopy), or nil
  def self.from(key, emergence_date)
    ->(date) { lai(key, (date - emergence_date).to_i) } if CURVES.key?(key)
  end
end

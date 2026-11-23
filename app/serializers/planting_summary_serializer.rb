# A planting's status and season so far (PlantingStatus), for dashboard cards and the field page.
# Depths are inches; recent is AD over the last RECENT_DAYS days, for sparklines. projection is
# each day ahead: the forecast's AD and, with an ensemble, its 10th–90th percentiles and the chance
# of reaching the threshold by then. crossing is when the projection first reaches the threshold.
# rain_group_id is the irrigation group whose rainfall setting the planting follows (null: its
# farm's, rain_farm_id). For a planting using only entered rain (use_model_precip false), dry_ad and dry_crossing are the same
# with no forecast rain (Q7); otherwise null.
class PlantingSummarySerializer < ApplicationSerializer
  RECENT_DAYS = 21

  attribute(:planting_id) { |status| status.planting.id }
  attribute(:plant_name) { |status| status.planting.plant.name }
  attribute(:variety) { |status| status.planting.variety }
  attribute(:season_start) { |status| status.planting.season_start }
  # Part of the field: its size, for labels ("Soybean, 100 × 20 ft")
  attribute(:partial) { |status| status.planting.partial? }
  attribute(:area_acres) { |status| status.planting.area_acres }
  attribute(:plot_length_ft) { |status| status.planting.plot_length_ft }
  attribute(:plot_width_ft) { |status| status.planting.plot_width_ft }
  attribute(:end_date) { |status| status.planting.end_date }
  attribute(:phase, &:phase)
  attribute(:status, &:status)
  # Not irrigated: status is its water stress (C26)
  attribute(:rainfed, &:rainfed?)
  # The water stress coefficient at today's AD: the share of its unstressed water use the crop
  # manages, 1 unstressed
  attribute(:ks, &:ks)
  attribute(:weather_pending, &:weather_pending?)
  attribute(:date) { |status| status.current&.inputs&.date }
  attribute(:ad) { |status| status.current&.result&.ad }
  attribute(:pct_moisture) { |status| status.current&.result&.pct_moisture }
  attribute(:taw) { |status| status.params.taw.round(WaterBalance::PRECISION) }
  attribute(:ad_max) { |status| status.params.ad_max.round(WaterBalance::PRECISION) }
  attribute(:ad_pwp) { |status| status.params.ad_pwp.round(WaterBalance::PRECISION) }
  attribute(:target_in) { |status| status.params.target_in&.round(WaterBalance::PRECISION) }
  attribute(:field_capacity_pct) { |status| (status.params.field_capacity * 100).round(2) }
  attribute(:wilting_point_pct) { |status| (status.params.perm_wilting_pt * 100).round(2) }
  attribute(:pct_at_ad_zero) { |status| status.params.pct_at_ad_zero.round(2) }
  attribute(:last_rain) { |status| (day = status.last_rain) && {date: day.inputs.date, inches: day.inputs.rain} }
  attribute(:last_irrigation) do |status|
    (day = status.last_irrigation) && {date: day.inputs.date, inches: day.inputs.irrigation}
  end
  attribute(:recent) do |status|
    status.days.last(RECENT_DAYS).map { |day| {date: day.inputs.date, ad: day.result.ad} }
  end
  attribute(:totals) { |status| status.totals.to_h }
  attribute(:threshold) { |status| status.threshold.round(WaterBalance::PRECISION) }
  attribute(:crossing) { |status| status.crossing&.to_h }
  attribute(:use_model_precip, &:use_model_precip?)
  attribute(:rain_group_id) { |status| status.planting.system.pivot_group_id }
  attribute(:rain_farm_id) { |status| status.planting.system.farm_id }
  attribute(:dry_crossing) { |status| status.dry_crossing&.to_h }
  attribute(:ensemble_size, &:ensemble_size)
  # forecast, or observed while time travelling: the projection is the weather that followed
  attribute(:projection_source, &:projection_source)
  # How the crop's curve was fitted to the readings (CanopyFit), when the canopy follows it and has some
  attribute(:canopy_fit) do |status|
    fit = status.canopy.fit
    fit && {shift: fit.shift, stretch: fit.stretch.round(3), height: fit.height.round(3)}
  end
  # Whether the percent cover curve runs by growing degree days at the planting's weather cell (C23):
  # true; false for a crop that would but whose cell has no normals yet; null for a curve that runs by
  # days (a crop not on degree days, or an LAI curve)
  attribute(:canopy_thermal) do |status|
    if status.canopy.thermal? then true
    elsif status.planting.thermal_curve? then false
    end
  end
  # Readings to enter and checks to make (PlantingTasks), while the season is on; date is the day
  # daily entry opens on for the task (the irrigation check's first day)
  attribute(:tasks) { |status| status.tasks.map(&:to_h) }
  attribute(:projection) do |status|
    bands = status.ensemble.index_by(&:date)
    dry = status.dry_projection.index_by(&:date)
    status.forecast_days.map do |day|
      band = bands[day.inputs.date]
      {date: day.inputs.date, ad: day.result.ad, p10: band&.p10, p50: band&.p50, p90: band&.p90, chance: band&.chance,
       dry_ad: dry[day.inputs.date]&.ad}
    end
  end

  typelize planting_id: :number, plant_name: :string, variety: "string | null", season_start: :string,
    partial: :boolean, area_acres: "number | null", plot_length_ft: "number | null", plot_width_ft: "number | null",
    end_date: :string, phase: "'upcoming' | 'active' | 'ended'",
    status: "'full' | 'ok' | 'caution' | 'irrigate' | 'no_stress' | 'stress_coming' | 'stressed' | 'needs_canopy' | null",
    rainfed: :boolean, ks: "number | null", weather_pending: :boolean, date: "string | null", ad: "number | null",
    pct_moisture: "number | null", taw: :number, ad_max: :number, ad_pwp: :number, target_in: "number | null",
    field_capacity_pct: :number, wilting_point_pct: :number, pct_at_ad_zero: :number,
    last_rain: "{ date: string; inches: number } | null", last_irrigation: "{ date: string; inches: number } | null",
    recent: "{ date: string; ad: number }[]",
    totals: "{ rain: number | null; irrigation: number; adj_et: number | null; deep_drainage: number; " \
      "rain_model: number | null; " \
      "entered_rain_days: number; entered_rain: number; entered_rain_model: number; " \
      "irrigation_days: number; rain_days: number; drainage_days: number; stress_days: number }",
    threshold: :number, crossing: "{ date: string; days: number; ad: number; refill: number } | null",
    use_model_precip: :boolean, rain_group_id: "number | null", rain_farm_id: :number, dry_crossing: "{ date: string; days: number; ad: number; refill: number } | null",
    ensemble_size: :number, projection_source: "'forecast' | 'observed'", canopy_fit: "{ shift: number; stretch: number; height: number } | null",
    canopy_thermal: "boolean | null",
    tasks: "{ kind: 'irrigation_check' | 'soil_moisture' | 'canopy' | 'canopy_check'; label: string; " \
      "last_date: string | null; due: boolean; note: 'due' | 'canopy closed' | 'vines killed' | 'optional' | null; " \
      "todo: string | null; message: string | null; date: string | null }[]",
    projection: "{ date: string; ad: number; p10: number | null; p50: number | null; p90: number | null; " \
      "chance: number | null; dry_ad: number | null }[]"
end

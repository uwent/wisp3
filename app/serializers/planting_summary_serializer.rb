# A planting's status and season so far (PlantingStatus), for dashboard cards and the field page.
# Depths are inches; recent is AD over the last RECENT_DAYS days, for sparklines.
class PlantingSummarySerializer < ApplicationSerializer
  RECENT_DAYS = 21

  attribute(:planting_id) { |status| status.planting.id }
  attribute(:plant_name) { |status| status.planting.plant.name }
  attribute(:variety) { |status| status.planting.variety }
  attribute(:season_start) { |status| status.planting.season_start }
  attribute(:end_date) { |status| status.planting.end_date }
  attribute(:phase, &:phase)
  attribute(:status, &:status)
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

  typelize planting_id: :number, plant_name: :string, variety: "string | null", season_start: :string,
    end_date: :string, phase: "'upcoming' | 'active' | 'ended'",
    status: "'full' | 'ok' | 'caution' | 'irrigate' | null", date: "string | null", ad: "number | null",
    pct_moisture: "number | null", taw: :number, ad_max: :number, ad_pwp: :number, target_in: "number | null",
    field_capacity_pct: :number, wilting_point_pct: :number, pct_at_ad_zero: :number,
    last_rain: "{ date: string; inches: number } | null", last_irrigation: "{ date: string; inches: number } | null",
    recent: "{ date: string; ad: number }[]",
    totals: "{ rain: number; irrigation: number; adj_et: number; deep_drainage: number; rain_model: number; " \
      "entered_rain_days: number; entered_rain: number; entered_rain_model: number }"
end

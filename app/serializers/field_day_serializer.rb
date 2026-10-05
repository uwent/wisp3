# One row of a field's daily grid: PlantingBalance::Day's resolved inputs (with sources), canopy
# and balance. params: entries {date => FieldEntry} for notes, observations {date => canopy
# reading}, pivot_inches {date => inches from the pivot} (shown when a field entry overrides it).
class FieldDaySerializer < ApplicationSerializer
  SOURCE = "'entered' | 'pivot' | 'group' | 'model' | 'forecast' | 'none' | 'missing'"

  attribute(:date) { |day| day.inputs.date }
  attribute(:et0) { |day| day.inputs.et0 }
  attribute(:et0_source) { |day| day.inputs.et0_source }
  attribute(:adj_et) { |day| day.result.adj_et }
  attribute(:et_source) { |day| day.result.et_source }
  attribute(:rain) { |day| day.inputs.rain }
  attribute(:rain_source) { |day| day.inputs.rain_source }
  attribute(:rain_model) { |day| day.inputs.rain_model }
  attribute(:irrigation) { |day| day.inputs.irrigation }
  attribute(:irrigation_source) { |day| day.inputs.irrigation_source }
  attribute(:pivot_inches) { |day| params[:pivot_inches][day.inputs.date] }
  attribute(:soil_moisture_pct) { |day| day.inputs.soil_moisture_pct }
  attribute(:moisture_source) { |day| day.inputs.moisture_source }
  attribute(:canopy) { |day| day.canopy.round(WaterBalance::PRECISION) }
  attribute(:canopy_entered) { |day| params[:observations][day.inputs.date] }
  attribute(:ad) { |day| day.result.ad }
  attribute(:pct_moisture) { |day| day.result.pct_moisture }
  attribute(:deep_drainage) { |day| day.result.deep_drainage }
  attribute(:notes) { |day| params[:entries][day.inputs.date]&.notes }

  typelize date: :string, et0: "number | null", et0_source: "'model' | 'forecast' | 'missing'", adj_et: "number | null",
    et_source: "'computed' | 'gap_fill' | 'missing'", rain: "number | null", rain_source: SOURCE,
    rain_model: "number | null", irrigation: "number | null", irrigation_source: SOURCE,
    pivot_inches: "number | null", soil_moisture_pct: "number | null", moisture_source: "'entered' | 'group' | null",
    canopy: :number, canopy_entered: "number | null", ad: :number, pct_moisture: :number, deep_drainage: :number,
    notes: "string | null"
end

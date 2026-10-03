require "csv"

# A planting's season as CSV: a header block describing the farm, field and crop, one row per day
# through today, and season totals. Columns follow the legacy export, plus the source of each
# input. Depths are in inches, as stored.
class PlantingCsv
  def initialize(status)
    @status = status
  end

  def to_csv
    planting, params = @status.planting, @status.params
    field = planting.field
    canopy = (planting.et_method == "lai") ? "Leaf area index" : "Percent cover"

    CSV.generate do |csv|
      csv << ["WISP daily report, #{planting.season_year} season"]
      csv << []
      csv << ["Farm", "Pivot", "Equipment", "Field", "Area (acres)"]
      csv << [field.pivot.farm.name, field.pivot.name, field.pivot.equipment, field.name, field.area_acres]
      csv << ["Soil type", "Field capacity (%)", "Wilting point (%)", "Target AD (%)"]
      csv << [field.soil_type.name, pct(params.field_capacity), pct(params.perm_wilting_pt), planting.target_ad_pct]
      csv << ["Crop", "Variety", "Root zone depth (in)", "MAD (%)", "Initial moisture (%)", "Emergence",
        "AD at field capacity (in)", "Season start", "Harvest or kill"]
      csv << [planting.plant.name, planting.variety, planting.max_root_zone_depth, pct(planting.mad_frac),
        planting.initial_moisture_pct || pct(params.field_capacity), planting.emergence_date, num(params.ad_max),
        planting.season_start, planting.end_date]
      csv << []
      csv << ["Date", "Reference ET (in)", "AD (in)", "Percent moisture", canopy, "Rainfall (in)", "Rain source",
        "Modeled rain (in)", "Irrigation (in)", "Irrigation source", "Soil moisture reading (%)", "Adjusted ET (in)",
        "ET source", "Deep drainage (in)"]
      @status.days.each do |day|
        inputs, result = day.inputs, day.result
        csv << [inputs.date, num(inputs.et0), num(result.ad), num(result.pct_moisture), num(day.canopy),
          num(inputs.rain), inputs.rain_source, num(inputs.rain_model), num(inputs.irrigation),
          inputs.irrigation_source, inputs.soil_moisture_pct, num(result.adj_et), result.et_source,
          num(result.deep_drainage)]
      end
      totals = @status.totals
      csv << []
      csv << ["Totals", nil, nil, nil, nil, num(totals.rain), nil, num(totals.rain_model), num(totals.irrigation), nil,
        nil, num(totals.adj_et), nil, num(totals.deep_drainage)]
    end
  end

  private

  def num(value) = value && format("%.4f", value)
  def pct(fraction) = (fraction * 100).round(2)
end

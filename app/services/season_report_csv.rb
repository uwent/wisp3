# An operation's season as one CSV, for its records (legacy's end-of-season report, for every field
# at once): frontmatter (CsvExport) with a short summary, then three sections, each a title line, a
# header and rows: the fields (each planting's crop and season totals), irrigation by pivot, and the
# weather by zone (the weather grid cell its pivots share). Seasons count through today. The daily
# detail is in each field's export and each pivot's weather export.
class SeasonReportCsv
  include CsvExport

  def initialize(group, year, exported_by: nil, about_url: nil, today: Date.current)
    @group, @year, @exported_by, @about_url, @today = group, year, exported_by, about_url, today
  end

  def to_csv
    generate do |csv|
      frontmatter(csv, "WISP season report, #{@year}", summary, exported_by: @exported_by, about_url: @about_url)
      fields_section(csv)
      csv << []
      pivots_section(csv)
      csv << []
      weather_section(csv)
    end
  end

  private

  def summary
    return {"Operation" => @group.name, "Season" => "no crops entered for #{@year}"} if statuses.empty?
    fields = statuses.map { |status| status.planting.field }.uniq
    pivots = fields.map(&:pivot).uniq
    farms = pivots.map(&:farm).uniq
    acres = fields.filter_map(&:area_acres)
    without_area = fields.size - acres.size
    {
      "Operation" => @group.name,
      "Season" => "#{@year}, counted through #{through}",
      "Fields" => "#{count(fields.size, "field")} on #{count(pivots.size, "pivot")} across #{count(farms.size, "farm")}, " \
        "#{acres.sum.round(1)} acres#{" (#{count(without_area, "field")} without an area)" if without_area.positive?}",
      "Irrigation" => spread(by_field { |totals| totals.irrigation }),
      "Rainfall" => spread(by_field { |totals| totals.rain }),
      "Sections" => "Fields; Irrigation by pivot; Weather by zone"
    }
  end

  def fields_section(csv)
    csv << ["Fields"]
    csv << ["Farm", "Pivot", "Equipment", "Field", "Area (acres)", "Crop", "Variety", "Soil type", "Season start",
      "Emergence", "Vine kill", "Harvest or kill", "Days counted", "Rainfall (in)", "Modeled rain (in)", "Irrigation (in)",
      "Days irrigated", "Adjusted ET (in)", "Deep drainage (in)", "Days at or below AD 0", "AD at end (in)",
      "Percent moisture at end", "Notes"]
    statuses.each do |status|
      planting, totals, last = status.planting, status.totals, status.current&.result
      field = planting.field
      csv << [text(field.pivot.farm.name), text(field.pivot.name), text(field.pivot.equipment), text(field.name),
        field.area_acres, planting.plant.name, text(planting.variety), field.soil_type.name, planting.season_start,
        planting.emergence_date, planting.vine_kill_date, planting.end_date, status.days.size, num(totals.rain), num(totals.rain_model),
        num(totals.irrigation), irrigated_dates(status).size, num(totals.adj_et), num(totals.deep_drainage),
        status.days.count { |day| day.result.ad <= 0 }, num(last&.ad), num(last&.pct_moisture), text(planting.notes)]
    end
  end

  # Each pivot's irrigation as the average over its fields, weighted by area when every field has one
  def pivots_section(csv)
    csv << ["Irrigation by pivot (the average of its fields' season irrigation, weighted by area where every field has one)"]
    csv << ["Farm", "Pivot", "Equipment", "Fields", "Area (acres)", "Days irrigated", "Irrigation (in)"]
    statuses.group_by { |status| status.planting.field.pivot }.each do |pivot, pivot_statuses|
      by_field = pivot_statuses.group_by { |status| status.planting.field }
        .transform_values { |field_statuses| field_statuses.sum { |status| status.totals.irrigation } }
      areas = by_field.keys.map(&:area_acres)
      average = if areas.all?
        by_field.sum { |field, inches| field.area_acres * inches } / areas.sum
      else
        by_field.values.sum / by_field.size
      end
      csv << [text(pivot.farm.name), text(pivot.name), text(pivot.equipment), by_field.size,
        areas.all? ? areas.sum : nil, pivot_statuses.flat_map { |status| irrigated_dates(status) }.uniq.size, num(average)]
    end
  end

  # Each zone's weather from its first planting's start through its last one's end (or today)
  def weather_section(csv)
    csv << ["Weather by zone (the weather grid cell its pivots share)"]
    csv << ["Zone", "Latitude", "Longitude", "Pivots", "From", "Through", "Days with weather", "Precipitation (in)",
      "Reference ET (in)", "GDD (50/86 °F)", "Mean temperature (°F)", "Highest (°F)", "Lowest (°F)"]
    zones = statuses.group_by { |status| status.planting.field.pivot.weather_cell }.except(nil)
    weather = weather_by_cell(zones.keys)
    zones.each_with_index do |(cell, cell_statuses), i|
      from = cell_statuses.map { |status| status.planting.season_start }.min
      to = [cell_statuses.map { |status| status.planting.end_date }.max, @today].min
      days = weather.fetch(cell.id, []).select { |day| (from..to).cover?(day[:date]) }
      pivots = cell_statuses.map { |status| status.planting.field.pivot.name }.uniq
      csv << [i + 1, cell.latitude, cell.longitude, text(pivots.join("; ")), from, to, days.size,
        num(total(days, :precip)), num(total(days, :et0)),
        num(total(days.map { |day| {gdd: Weather::DegreeDays.daily(day[:tmax], day[:tmin])} }, :gdd)),
        num(mean(days, :tmean)), num(days.filter_map { |day| day[:tmax] }.max), num(days.filter_map { |day| day[:tmin] }.min)]
    end
  end

  # The year's plantings, by farm, pivot and field, with their balances (inputs preloaded as on the dashboard)
  def statuses
    @statuses ||= begin
      plantings = @group.plantings.where(season_start: Date.new(@year).all_year)
        .includes(:plant, :canopy_observations, field: [:soil_type, {pivot: [:weather_cell, {farm: :group}]}])
        .sort_by { |p| [p.field.pivot.farm.name, p.field.pivot.name, p.field.name, p.season_start] }
      if plantings.empty?
        []
      else
        fields = plantings.map(&:field).uniq
        dates = plantings.map(&:season_start).min..[plantings.map(&:end_date).max, @today].min
        records = DailyInputs.preload(fields, dates)
        weather = WeatherDay.balance_inputs_by_cell(fields.map { |field| field.pivot.weather_cell_id }.uniq, dates)
        plantings.map do |planting|
          field = planting.field
          PlantingStatus.new(planting, today: @today, records: records[field.id],
            weather: weather.fetch(field.pivot.weather_cell_id, {}), ensemble: [])
        end
      end
    end
  end

  # A season total for each field, adding up its plantings (a field can grow two crops in a year);
  # nil for a field none of whose plantings has one
  def by_field
    statuses.group_by { |status| status.planting.field }.values.map do |field_statuses|
      values = field_statuses.filter_map { |status| yield status.totals }
      values.sum if values.any?
    end
  end

  # The last day counted: today, or the last season's end
  def through = [statuses.map { |status| status.planting.end_date }.max, @today].min

  def weather_by_cell(cells)
    return {} if cells.empty?
    WeatherDay.where(weather_cell_id: cells.map(&:id), date: Date.new(@year).all_year)
      .pluck(:weather_cell_id, :date, :precip_in, :et0_in, :tmax_f, :tmin_f, :tmean_f)
      .group_by(&:first).transform_values do |rows|
        rows.map { |_, date, precip, et0, tmax, tmin, tmean| {date:, precip:, et0:, tmax:, tmin:, tmean:} }
      end
  end

  def irrigated_dates(status) = status.days.select { |day| day.inputs.irrigation.to_f.positive? }.map { |day| day.inputs.date }

  # A total over the days that have a value; nil (missing, not zero) when none does
  def total(days, key)
    values = days.filter_map { |day| day[key] }
    values.sum if values.any?
  end

  def mean(days, key)
    values = days.filter_map { |day| day[key] }
    values.sum / values.size if values.any?
  end

  # "0.00 to 8.40 in by field, 5.20 in on average" (or one amount when every field had the same)
  def spread(values)
    values = values.compact
    return "none counted yet" if values.empty?
    low, high = values.minmax.map { |value| format("%.2f", value) }
    return "#{low} in#{" on every field" if values.size > 1}" if low == high
    "#{low} to #{high} in by field, #{format("%.2f", values.sum / values.size)} in on average"
  end

  def count(n, noun) = "#{n} #{noun.pluralize(n)}"
end

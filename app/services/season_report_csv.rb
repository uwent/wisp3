# An operation's season as one CSV, for its records (legacy's end-of-season report, for every field
# at once): frontmatter (CsvExport) with a short summary, then three sections, each a title line, a
# header and rows: the fields (each planting's crop and season totals), irrigation by system, and the
# weather by zone (the weather grid cell its systems share). Seasons count through today. Irrigation's
# spread and averages leave out rainfed plantings that weren't irrigated (D17), whose zero isn't a
# system's. The daily detail is in each field's export and each system's weather export.
class SeasonReportCsv
  include CsvExport

  def initialize(group, year, exported_by: nil, about_url: nil, today: Current.today)
    @group, @year, @exported_by, @about_url, @today = group, year, exported_by, about_url, today
  end

  def to_csv
    generate do |csv|
      frontmatter(csv, "WISP season report, #{@year}", summary.merge(weather_corrections), exported_by: @exported_by, about_url: @about_url)
      fields_section(csv)
      csv << []
      systems_section(csv)
      csv << []
      weather_section(csv)
    end
  end

  private

  def summary
    return {"Operation" => @group.name, "Season" => "no crops entered for #{@year}"} if statuses.empty?
    fields = statuses.map { |status| status.planting.field }.uniq
    systems = statuses.map { |status| status.planting.system }.uniq
    farms = systems.map(&:farm).uniq
    acres = fields.filter_map { |field| field_areas[field] }
    without_area = fields.size - acres.size
    {
      "Operation" => @group.name,
      "Season" => "#{@year}, counted through #{through}",
      "Fields" => "#{count(fields.size, "field")} on #{count(systems.size, "system")} across #{count(farms.size, "farm")}, " \
        "#{acres.sum.round(1)} acres#{" (#{count(without_area, "field")} without an area)" if without_area.positive?}",
      "Irrigation" => spread(by_field(irrigated) { |totals| totals.irrigation }),
      "Rainfall" => spread(by_field { |totals| totals.rain }),
      "Sections" => "Fields; Irrigation by irrigation system; Weather by zone"
    }
  end

  def fields_section(csv)
    csv << ["Fields"]
    csv << ["Farm", "Irrigation system", "Kind", "Equipment", "Field", "Area (acres)", "Part of the field", "Crop", "Variety", "Water", "Soil type", "Season start",
      "Emergence", "Vine kill", "Harvest or kill", "Days counted", "Rainfall (in)", "Modeled rain (in)", "Irrigation (in)",
      "Days irrigated", "Adjusted ET (in)", "Deep drainage (in)", "Days below AD 0", "AD at end (in)",
      "Percent moisture at end", "Notes"]
    statuses.each do |status|
      planting, totals, last = status.planting, status.totals, status.current&.result
      field, system = planting.field, planting.system
      csv << [text(system.farm.name), text(system.name), system.kind_name, text(system.equipment),
        text(field.name), planting.area_acres, planting.size_label, planting.plant.name, text(planting.variety),
        planting.rainfed? ? "Rainfed" : "Irrigated", planting.soil_type.name, planting.season_start,
        planting.emergence_date, planting.vine_kill_date, planting.end_date, status.days.size, num(totals.rain), num(totals.rain_model),
        num(totals.irrigation), totals.irrigation_days, num(totals.adj_et), num(totals.deep_drainage),
        totals.stress_days, num(last&.ad), num(last&.pct_moisture), text(planting.notes)]
    end
  end

  # Each irrigation system's irrigation as the average over its fields, weighted by area when every
  # field has one; rainfed plantings that weren't irrigated left out
  def systems_section(csv)
    csv << ["Irrigation by irrigation system (the average of its irrigated fields' season irrigation, weighted by area where every field has one)"]
    csv << ["Farm", "Irrigation system", "Kind", "Equipment", "Fields", "Area (acres)", "Days irrigated", "Irrigation (in)"]
    irrigated.group_by { |status| status.planting.system }.each do |system, system_statuses|
      by_field = system_statuses.group_by { |status| status.planting.field }
        .transform_values { |field_statuses| field_total(field_statuses, &:irrigation) }
      areas = by_field.keys.map { |field| field_areas[field] }
      average = if areas.all?
        by_field.sum { |field, inches| field_areas[field] * inches } / areas.sum
      else
        by_field.values.sum / by_field.size
      end
      csv << [text(system.farm.name), text(system.name), system.kind_name, text(system.equipment), by_field.size,
        areas.all? ? areas.sum : nil, system_statuses.flat_map { |status| irrigated_dates(status) }.uniq.size, num(average)]
    end
  end

  # Each zone's weather from its first planting's start through its last one's end (or today)
  def weather_section(csv)
    csv << ["Weather by zone (the weather grid cell its irrigation systems share)"]
    csv << ["Zone", "Latitude", "Longitude", "Irrigation systems", "From", "Through", "Days with weather", "Precipitation (in)",
      "Reference ET (in)", "GDD (50/86 °F)", "Mean temperature (°F)", "Highest (°F)", "Lowest (°F)"]
    # The weather each planting ran on (where its system was that season)
    zones = statuses.group_by { |status| status.planting.weather_cell }.except(nil)
    weather = weather_by_cell(zones.keys)
    zones.each_with_index do |(cell, cell_statuses), i|
      from = cell_statuses.map { |status| status.planting.season_start }.min
      to = [cell_statuses.map { |status| status.planting.end_date }.max, @today].min
      days = weather.fetch(cell.id, []).select { |day| (from..to).cover?(day[:date]) }
      systems = cell_statuses.map { |status| status.planting.system.label }.uniq
      csv << [i + 1, cell.latitude, cell.longitude, text(systems.join("; ")), from, to, days.size,
        num(total(days, :precip)), num(total(days, :et0)),
        num(total(days.map { |day| {gdd: Weather::DegreeDays.daily(day[:tmax], day[:tmin])} }, :gdd)),
        num(mean(days, :tmean)), num(days.filter_map { |day| day[:tmax] }.max), num(days.filter_map { |day| day[:tmin] }.min)]
    end
  end

  # The year's plantings, by farm, irrigation system and field, with their balances (inputs preloaded as on the dashboard)
  def statuses
    @statuses ||= begin
      plantings = @group.plantings.where(season_start: Date.new(@year).all_year)
        .includes(:plant, :canopy_observations, :canopy_cuttings, :soil_type, :weather_cell,
          system: [:irrigation_group, {farm: :group}], field: {system: [:irrigation_group, {farm: :group}]})
        .sort_by { |p| [p.system.farm.name, p.system.name, p.field.name, p.season_start] }
      if plantings.empty?
        []
      else
        fields = plantings.map(&:field).uniq
        dates = plantings.map(&:season_start).min..[plantings.map(&:end_date).max, @today].min
        records = DailyInputs.preload(fields, dates)
        weather = WeatherDay.balance_inputs_by_cell(plantings.map(&:weather_cell_id).uniq, dates)
        temperatures = CellTemperatures.for_plantings(plantings)
        plantings.map do |planting|
          PlantingStatus.new(planting, today: @today, records: records[planting.field_id],
            weather: weather.fetch(planting.weather_cell_id, {}), ensemble: [],
            temperatures: temperatures[planting.weather_cell_id])
        end
      end
    end
  end

  # The plantings irrigation is counted over: not a rainfed one that wasn't irrigated (D17)
  def irrigated
    @irrigated ||= statuses.reject { |status| status.rainfed? && status.totals.irrigation_days.zero? }
  end

  # A season total for each field (field_total); nil for a field none of whose plantings has one
  def by_field(over = statuses, &value)
    over.group_by { |status| status.planting.field }.values.map { |field_statuses| field_total(field_statuses, &value) }
  end

  # A field's season total of a value of its plantings' totals: its whole-field plantings' added up
  # (a field can grow two crops in a year), a plot within one left out (D19); for a field of plots
  # only, their totals weighted by area over the most ground they covered at once, so plots side by
  # side average and plots one after another add up. nil when none has the value.
  def field_total(field_statuses)
    whole = field_statuses.reject { |status| status.planting.partial? }
    if whole.any?
      values = whole.filter_map { |status| yield status.totals }
      return values.sum if values.any?
      return nil
    end
    valued = field_statuses.filter_map do |status|
      value = yield status.totals
      [status.planting, value] unless value.nil?
    end
    return nil if valued.empty?
    valued.sum { |plot, value| plot.area_acres * value } / most_at_once(valued.map(&:first))
  end

  # The most acres plots were in season together on any day (the total only rises when one starts)
  def most_at_once(plots)
    plots.map(&:season_start).map { |date| plots.select { |plot| plot.season_range.cover?(date) }.sum(&:area_acres) }.max
  end

  # Each field's area that year, as its whole-field plantings kept it (the
  # larger, for a double crop), or for a field of plots only, the field's; nil without one
  def field_areas
    @field_areas ||= statuses.group_by { |status| status.planting.field }.to_h do |field, field_statuses|
      whole = field_statuses.map(&:planting).reject(&:partial?)
      [field, whole.any? ? whole.filter_map(&:area_acres).max : field.area_acres]
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

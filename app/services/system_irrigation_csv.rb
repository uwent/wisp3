# An irrigation system's irrigation for a year as CSV: frontmatter (CsvExport),
# then a row per day and field it watered (IrrigationSystem#irrigation_on; irrigation is stored per field,
# D15), oldest first. A plot's own irrigation is on its planting's export, except a rainfed crop's
# irrigated plots, which the system waters in the field's place (Field.system_irrigation).
class SystemIrrigationCsv
  include CsvExport

  def initialize(system, year, exported_by: nil, about_url: nil)
    @system, @year, @exported_by, @about_url = system, year, exported_by, about_url
  end

  def to_csv
    days = @system.irrigation_on(Date.new(@year).all_year)
    entries = days.values.flat_map(&:values)
    generate do |csv|
      frontmatter(csv, "WISP irrigation, #{@system.label}, #{@year}", {
        "Operation" => @system.farm.group.name,
        "Irrigation system" => "#{@system.farm.name} / #{@system.label}",
        "Equipment" => @system.equipment,
        "Days" => "#{days.size}, #{entries.size} field entries totaling #{format("%.2f", entries.sum(&:irrigation_in))} in",
        "Not included" => "a plot's own irrigation (each planting's export has it), except under a rainfed crop, where the field's row is its irrigated plots'"
      }, exported_by: @exported_by, about_url: @about_url)
      csv << ["Date", "Field", "Irrigation (in)", "Notes"]
      days.each do |date, fields|
        fields.each { |field, entry| csv << [date, text(field.name), num(entry.irrigation_in), text(entry.notes)] }
      end
    end
  end
end

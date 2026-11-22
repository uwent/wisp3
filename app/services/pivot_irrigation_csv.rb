# An irrigation system's (a pivot's, in code) irrigation for a year as CSV: frontmatter (CsvExport),
# then a row per day and field it watered (Pivot#irrigation_on; irrigation is stored per field,
# D15), oldest first. A plot's own irrigation is on its planting's export.
class PivotIrrigationCsv
  include CsvExport

  def initialize(pivot, year, exported_by: nil, about_url: nil)
    @pivot, @year, @exported_by, @about_url = pivot, year, exported_by, about_url
  end

  def to_csv
    days = @pivot.irrigation_on(Date.new(@year).all_year)
    entries = days.values.flat_map(&:values)
    generate do |csv|
      frontmatter(csv, "WISP irrigation, #{@pivot.label}, #{@year}", {
        "Operation" => @pivot.farm.group.name,
        "Irrigation system" => "#{@pivot.farm.name} / #{@pivot.label}",
        "Equipment" => @pivot.equipment,
        "Days" => "#{days.size}, #{entries.size} field entries totaling #{format("%.2f", entries.sum(&:irrigation_in))} in",
        "Not included" => "a plot's own irrigation (each planting's export has it)"
      }, exported_by: @exported_by, about_url: @about_url)
      csv << ["Date", "Field", "Irrigation (in)", "Notes"]
      days.each do |date, fields|
        fields.each { |field, entry| csv << [date, text(field.name), num(entry.irrigation_in), text(entry.notes)] }
      end
    end
  end
end

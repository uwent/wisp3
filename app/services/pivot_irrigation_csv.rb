# An irrigation system's (a pivot's, in code) irrigation entries for a year as CSV: frontmatter (CsvExport), then one row per entry
# with the amount as entered and as applied (the percent timer or run hours converted to inches),
# oldest first.
class PivotIrrigationCsv
  include CsvExport

  def initialize(pivot, year, irrigations, exported_by: nil, about_url: nil)
    @pivot, @year, @irrigations, @exported_by, @about_url = pivot, year, irrigations, exported_by, about_url
  end

  def to_csv
    names = @pivot.fields.to_h { |field| [field.id, field.name] }
    generate do |csv|
      frontmatter(csv, "WISP irrigation, #{@pivot.label}, #{@year}", {
        "Operation" => @pivot.farm.group.name,
        "Irrigation system" => "#{@pivot.farm.name} / #{@pivot.label}",
        "Equipment" => @pivot.equipment,
        "Depth at 100% (in)" => @pivot.inches_at_100,
        "Entries" => "#{@irrigations.size}, totaling #{format("%.2f", @irrigations.sum { |i| i.applied_inches.to_f })} in applied",
        "Not included" => "irrigation entered on a field itself (each field's export has it)"
      }, exported_by: @exported_by, about_url: @about_url)
      csv << ["Date", "Inches entered", "Run hours entered", "Percent timer entered", "Circles at that percent",
        "Applied (in)", "Applied to", "Notes"]
      @irrigations.each do |irrigation|
        fields = irrigation.field_ids.nil? ? "All fields" : irrigation.field_ids.filter_map { |id| names[id] }.join("; ")
        circles = (irrigation.circles || 1 if irrigation.percent_timer)
        csv << [irrigation.date, num(irrigation.inches), irrigation.run_hours, irrigation.percent_timer, circles,
          num(irrigation.applied_inches),
          text(fields), text(irrigation.notes)]
      end
    end
  end
end

# A pivot's irrigation entries for a year as CSV: frontmatter (CsvExport), then one row per entry
# with the amount as entered and as applied (run hours converted to inches), oldest first.
class PivotIrrigationCsv
  include CsvExport

  def initialize(pivot, year, irrigations, exported_by: nil, about_url: nil)
    @pivot, @year, @irrigations, @exported_by, @about_url = pivot, year, irrigations, exported_by, about_url
  end

  def to_csv
    names = @pivot.fields.to_h { |field| [field.id, field.name] }
    generate do |csv|
      frontmatter(csv, "WISP pivot irrigation, #{@pivot.name}, #{@year}", {
        "Operation" => @pivot.farm.group.name,
        "Pivot" => "#{@pivot.farm.name} / #{@pivot.name}",
        "Equipment" => @pivot.equipment,
        "Entries" => "#{@irrigations.size}, totaling #{format("%.2f", @irrigations.sum { |i| i.applied_inches.to_f })} in applied",
        "Not included" => "irrigation entered on a field itself (each field's export has it)"
      }, exported_by: @exported_by, about_url: @about_url)
      csv << ["Date", "Inches entered", "Run hours entered", "Applied (in)", "Applied to", "Notes"]
      @irrigations.each do |irrigation|
        fields = irrigation.field_ids.nil? ? "All fields" : irrigation.field_ids.filter_map { |id| names[id] }.join("; ")
        csv << [irrigation.date, num(irrigation.inches), irrigation.run_hours, num(irrigation.applied_inches),
          text(fields), text(irrigation.notes)]
      end
    end
  end
end

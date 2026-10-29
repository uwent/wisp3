require "rails_helper"

RSpec.describe SeasonReportCsv do
  let(:user) { create(:user, first_name: "Jane", last_name: "Grower") }
  let(:group) { user.groups.first }
  let(:farm) { create(:farm, group:, name: "Hancock") }
  let(:pivot) { create(:pivot, farm:, name: "North", equipment: "=Well 12") }
  let(:east) { create(:field, pivot:, name: "East", area_acres: 30) }
  let(:west) { create(:field, pivot:, name: "West", area_acres: 90) }
  let(:today) { Date.new(2026, 7, 10) }
  let(:rows) { CSV.parse(described_class.new(group, 2026, exported_by: user, about_url: "https://wisp.test/about", today:).to_csv.delete_prefix(CsvExport::BOM)) }

  def section(title)
    start = rows.index { |row| row.first == title || row.first&.start_with?("#{title} (") }
    header = rows[start + 1]
    rows[(start + 2)..].take_while(&:any?).map { |row| header.zip(row).to_h }
  end

  before do
    [east, west].each do |field|
      create(:planting, field:, season_start: Date.new(2026, 7, 1), emergence_date: Date.new(2026, 7, 1),
        end_date: Date.new(2026, 9, 30))
    end
    (Date.new(2026, 7, 1)..today).each do |date|
      pivot.weather_cell.weather_days.create!(date:, et0_in: 0.2, precip_in: 0.1, tmax_f: 80, tmin_f: 60, tmean_f: 70,
        model: "m", hours: 24, fetched_at: Time.current)
    end
    pivot.pivot_irrigations.create!(date: Date.new(2026, 7, 3), inches: 0.6)
    east.field_entries.create!(date: Date.new(2026, 7, 5), irrigation_in: 0.4)
    create(:planting, field: create(:field, pivot:), season_start: Date.new(2025, 5, 1)) # another season
  end

  it "opens with frontmatter: what it covers, who exported it and when, and a summary" do
    travel_to(Time.zone.local(2026, 7, 10, 14, 30)) do
      expect(rows.first).to eq(["WISP season report, 2026"])
      frontmatter = rows[1..].take_while(&:any?).map(&:sole)
      expect(frontmatter).to include("Operation: #{group.name}", "Season: 2026, counted through 2026-07-10",
        "Fields: 2 fields on 1 pivot across 1 farm, 120.0 acres", "Irrigation: 0.60 to 1.00 in by field, 0.80 in on average",
        "Exported by: Jane Grower (#{user.email})", "Exported: 2026-07-10 14:30 CDT", "Details: https://wisp.test/about")
    end
  end

  it "lists each field's season, then irrigation by pivot, then the weather by zone" do
    fields = section("Fields")
    expect(fields.map { |row| row["Field"] }).to eq(%w[East West])
    expect(fields.first).to include("Pivot" => "North", "Equipment" => "'=Well 12", "Days counted" => "10",
      "Irrigation (in)" => "1.0000", "Days irrigated" => "2", "Rainfall (in)" => "1.0000", "Season start" => "2026-07-01")

    pivot_row = section("Irrigation by pivot").sole
    # (30 × 1.0 + 90 × 0.6) / 120 acres
    expect(pivot_row).to include("Fields" => "2", "Area (acres)" => "120.0", "Days irrigated" => "2", "Irrigation (in)" => "0.7000")

    zone = section("Weather by zone").sole
    expect(zone).to include("Zone" => "1", "Pivots" => "North", "From" => "2026-07-01", "Through" => "2026-07-10",
      "Days with weather" => "10", "Precipitation (in)" => "1.0000", "Reference ET (in)" => "2.0000",
      "GDD (50/86 °F)" => "200.0000", "Mean temperature (°F)" => "70.0000")
  end

  it "averages a pivot's irrigation by field when a field has no area" do
    west.update!(area_acres: nil)
    expect(rows).to include(["Fields: 2 fields on 1 pivot across 1 farm, 30.0 acres (1 field without an area)"])
    # The pivot's area is unknown, so (1.0 + 0.6) / 2 fields rather than weighted by area
    expect(section("Irrigation by pivot").sole).to include("Area (acres)" => nil, "Irrigation (in)" => "0.8000")
  end

  it "leaves a field whose season hasn't started blank, not zero" do
    later = create(:field, pivot:, name: "Later", area_acres: 10)
    create(:planting, field: later, season_start: Date.new(2026, 8, 1), emergence_date: Date.new(2026, 8, 1),
      end_date: Date.new(2026, 10, 30))
    row = section("Fields").find { |r| r["Field"] == "Later" }
    expect(row).to include("Days counted" => "0", "Irrigation (in)" => "0.0000", "Rainfall (in)" => nil,
      "Adjusted ET (in)" => nil, "AD at end (in)" => nil, "Percent moisture at end" => nil)
  end

  it "gives each field's vine kill date, blank where there's none" do
    east.plantings.sole.update!(plant: create(:plant, key: "potato"), vine_kill_date: Date.new(2026, 9, 10))
    expect(section("Fields").map { |row| [row["Field"], row["Vine kill"]] }).to eq([["East", "2026-09-10"], ["West", nil]])
  end

  it "says so for a season without crops" do
    rows = CSV.parse(described_class.new(group, 2030, today:).to_csv.delete_prefix(CsvExport::BOM))
    expect(rows).to include(["Season: no crops entered for 2030"])
    expect(section_rows(rows)).to be_empty
  end

  def section_rows(rows) = rows[(rows.index(["Fields"]) + 2)..].take_while(&:any?)
end

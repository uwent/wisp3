require "rails_helper"

RSpec.describe PlantingCsv do
  let(:farm) { create(:farm, name: "Hancock") }
  let(:pivot) { create(:pivot, farm:, name: "=HYPERLINK(\"http://example.com\")", equipment: "+Zimmatic") }
  let(:field) { create(:field, pivot:, name: "North", area_acres: 60) }
  let(:planting) do
    create(:planting, field:, variety: "@Russet", season_start: Date.new(2026, 7, 1), emergence_date: Date.new(2026, 7, 1),
      end_date: Date.new(2026, 7, 31))
  end
  let(:weather) { (Date.new(2026, 7, 1)..Date.new(2026, 7, 31)).to_h { |date| [date, {et0: 0.2, precip: 0.0}] } }
  let(:rows) { CSV.parse(described_class.new(PlantingStatus.new(planting, today: Date.new(2026, 7, 10), weather:)).to_csv) }

  before { field.field_entries.create!(date: Date.new(2026, 7, 3), rain_in: 0.5, irrigation_in: 0.4) }

  it "describes the field and crop, then one row per day through today, then totals" do
    expect(rows.first).to eq(["WISP daily report, 2026 season"])
    header = rows.index { |row| row.first == "Date" }
    days = rows[(header + 1)..].take_while(&:any?)
    expect(days.size).to eq(10)
    expect(days.map(&:first)).to eq((Date.new(2026, 7, 1)..Date.new(2026, 7, 10)).map(&:iso8601))

    columns = rows[header]
    entered = days.find { |row| row.first == "2026-07-03" }.then { |row| columns.zip(row).to_h }
    expect(entered).to include("Rainfall (in)" => "0.5000", "Rain source" => "entered", "Modeled rain (in)" => "0.0000",
      "Irrigation (in)" => "0.4000", "Irrigation source" => "entered", "Reference ET (in)" => "0.2000")

    totals = rows.last
    expect(totals.first).to eq("Totals")
    expect(totals[columns.index("Rainfall (in)")]).to eq("0.5000")
    expect(totals[columns.index("Irrigation (in)")]).to eq("0.4000")
  end

  it "escapes names a spreadsheet would run as formulas, but not numbers" do
    expect(rows[3]).to eq(["Hancock", "'=HYPERLINK(\"http://example.com\")", "'+Zimmatic", "North", "60.0"])
    expect(rows[7][1]).to eq("'@Russet")
  end
end

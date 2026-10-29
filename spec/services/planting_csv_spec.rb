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
  let(:csv) { described_class.new(PlantingStatus.new(planting, today: Date.new(2026, 7, 10), weather:)).to_csv }
  let(:rows) { CSV.parse(csv.delete_prefix(CsvExport::BOM)) }

  before { field.field_entries.create!(date: Date.new(2026, 7, 3), rain_in: 0.5, irrigation_in: 0.4) }

  it "starts with a byte order mark, so Excel reads it as UTF-8" do
    expect(csv).to start_with(CsvExport::BOM)
  end

  it "describes the field and crop, then one row per day through today, then totals" do
    expect(rows.first).to eq(["WISP daily report, 2026 season"])
    expect(rows).to include(["Days: 2026-07-01 to 2026-07-10, one row each"])
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

  it "names the canopy column by the planting's method" do
    header = ->(rows) { rows.find { |row| row.first == "Date" } }
    expect(header.call(rows)).to include("Percent cover")
    planting.update!(plant: create(:plant, :field_corn), et_method: "lai")
    lai = CSV.parse(described_class.new(PlantingStatus.new(planting.reload, today: Date.new(2026, 7, 10), weather:))
      .to_csv.delete_prefix(CsvExport::BOM))
    expect(header.call(lai)).to include("Leaf area index").and(satisfy { |row| row.none? { |column| column.start_with?("Percent cover") } })
  end

  it "gives the vine kill date with the season's dates" do
    planting.update!(plant: create(:plant, key: "potato"), vine_kill_date: Date.new(2026, 7, 20))
    crop_header = rows.index { |row| row.first == "Crop" }
    crop = rows[crop_header].zip(rows[crop_header + 1]).to_h
    expect(crop).to include("Season start" => "2026-07-01", "Vine kill" => "2026-07-20", "Harvest or kill" => "2026-07-31")
  end

  it "says there are no days yet before the season starts" do
    upcoming = CSV.parse(described_class.new(PlantingStatus.new(planting, today: Date.new(2026, 6, 20), weather:))
      .to_csv.delete_prefix(CsvExport::BOM))
    expect(upcoming).to include(["Days: none yet"])
  end

  it "escapes names a spreadsheet would run as formulas, but not numbers" do
    farm_row = rows.index(["Farm", "Pivot", "Equipment", "Field", "Area (acres)"]) + 1
    expect(rows[farm_row]).to eq(["Hancock", "'=HYPERLINK(\"http://example.com\")", "'+Zimmatic", "North", "60.0"])
    expect(rows[farm_row + 4][1]).to eq("'@Russet")
  end
end

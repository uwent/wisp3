require "rails_helper"

RSpec.describe SystemIrrigationCsv do
  let(:system) { create(:system, name: "North", inches_at_100: 0.2) }
  let!(:east) { create(:field, system:, name: "East", area_acres: 10) }
  let!(:west) { create(:field, system:, name: "West", area_acres: 10) }

  it "lists each field's irrigation on the days the system watered it" do
    east.field_entries.create!(date: Date.new(2026, 7, 3), irrigation_in: 0.5, notes: "-first pass")
    west.field_entries.create!(date: Date.new(2026, 7, 3), irrigation_in: 0.5)
    east.field_entries.create!(date: Date.new(2026, 7, 8), irrigation_in: 0.0)
    west.field_entries.create!(date: Date.new(2026, 7, 9), rain_in: 0.4) # no irrigation
    west.field_entries.create!(date: Date.new(2025, 7, 9), irrigation_in: 1.0) # another year
    create(:field, name: "Elsewhere").field_entries.create!(date: Date.new(2026, 7, 3), irrigation_in: 0.9)

    rows = CSV.parse(described_class.new(system, 2026).to_csv.delete_prefix(CsvExport::BOM))
    expect(rows.first).to eq(["WISP irrigation, North (pivot), 2026"])
    expect(rows).to include(["Days: 2, 3 field entries totaling 1.00 in"])
    header = rows.index { |row| row.first == "Date" }
    expect(rows[header]).to eq(["Date", "Field", "Irrigation (in)", "Notes"])
    expect(rows[(header + 1)..]).to eq([["2026-07-03", "East", "0.5000", "'-first pass"],
      ["2026-07-03", "West", "0.5000", nil],
      ["2026-07-08", "East", "0.0000", nil]])
  end
end

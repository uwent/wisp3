require "rails_helper"

RSpec.describe PivotIrrigationCsv do
  let(:pivot) { create(:pivot, name: "North", pump_capacity_gpm: 27_154.0 * 20 / 600, inches_at_100: 0.2) }
  let!(:east) { create(:field, pivot:, name: "East", area_acres: 10) }
  let!(:west) { create(:field, pivot:, name: "West", area_acres: 10) }

  it "lists the entries with the amount applied" do
    pivot.pivot_irrigations.create!(date: Date.new(2026, 7, 3), inches: 0.5, notes: "-first pass")
    pivot.pivot_irrigations.create!(date: Date.new(2026, 7, 8), run_hours: 10, field_ids: [east.id])
    pivot.pivot_irrigations.create!(date: Date.new(2026, 7, 12), percent_timer: 40, circles: 0.5)
    rows = CSV.parse(described_class.new(pivot, 2026, pivot.pivot_irrigations.order(:date)).to_csv.delete_prefix(CsvExport::BOM))
    expect(rows.first).to eq(["WISP irrigation, North (pivot), 2026"])
    header = rows.index { |row| row.first == "Date" }
    data = rows[(header + 1)..]
    # 905 gpm × 600 min / (27,154 gal per acre-inch × 10 acres)
    # 0.2 in at 100% × 100 ÷ 40% × half a circle
    expect(data).to eq([["2026-07-03", "0.5000", nil, nil, nil, "0.5000", "All fields", "'-first pass"],
      ["2026-07-08", nil, "10.0", nil, nil, "2.0000", "East", nil],
      ["2026-07-12", nil, nil, "40.0", "0.5", "0.2500", "All fields", nil]])
    expect(rows).to include(["Entries: 3, totaling 2.75 in applied"], ["Depth at 100% (in): 0.2"])
  end
end

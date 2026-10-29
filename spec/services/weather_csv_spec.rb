require "rails_helper"

RSpec.describe WeatherCsv do
  let(:pivot) { create(:pivot, name: "North") }
  let(:dates) { Date.new(2026, 7, 1)..Date.new(2026, 7, 3) }

  before do
    pivot.weather_cell.weather_days.create!(date: Date.new(2026, 7, 1), et0_in: 0.21, tmax_f: 80, tmin_f: 60,
      soil_moisture_0_7cm: 0.25, model: "m", hours: 24, fetched_at: Time.current)
    pivot.weather_cell.weather_forecasts.create!(issued_at: 1.hour.ago, model: "m",
      payload: {days: [{date: "2026-07-02", tmax_f: 90, tmin_f: 70}]})
  end

  it "has a label for every stored weather variable" do
    expect(described_class::COLUMNS.keys).to eq(WeatherPanel::COLUMNS)
  end

  it "opens with frontmatter, then one row per day with every variable, forecast days marked" do
    days = WeatherPanel.new(pivot.weather_cell, dates, emergence_date: dates.first).days
    rows = CSV.parse(described_class.new(pivot, 2026, days).to_csv.delete_prefix(CsvExport::BOM))
    expect(rows.first).to eq(["WISP weather, North, 2026"])
    expect(rows).to include(["Days: 2026-07-01 to 2026-07-02, one row each; the last is from the latest forecast"])
    header = rows.index { |row| row.first == "Date" }
    data = rows[(header + 1)..].map { |row| rows[header].zip(row).to_h }
    expect(data.map { |row| [row["Date"], row["Forecast"]] }).to eq([%w[2026-07-01 no], %w[2026-07-02 yes]])
    expect(data.first).to include("Reference ET (in)" => "0.2100", "Soil moisture, 0–3 in (m³/m³)" => "0.2500",
      "Precipitation (in)" => nil, "GDD (50/86 °F)" => "20.0000")
    expect(data.last).to include("GDD since the first day (50/86 °F)" => "48.0000")
  end

  it "gives the cell's elevation, and says how many days are forecast" do
    cell = pivot.weather_cell
    cell.update!(elevation_m: 300.4)
    cell.weather_forecasts.create!(issued_at: Time.current, model: "m",
      payload: {days: [{date: "2026-07-02", tmax_f: 90}, {date: "2026-07-03", tmax_f: 91}]})
    rows = CSV.parse(described_class.new(pivot, 2026, WeatherPanel.new(cell, dates, emergence_date: dates.first).days)
      .to_csv.delete_prefix(CsvExport::BOM))
    expect(rows).to include(["Location: the weather grid cell centered at #{cell.latitude}, #{cell.longitude}, 300 m above sea level"],
      ["Days: 2026-07-01 to 2026-07-03, one row each; the last 2 are from the latest forecast"])

    stored_only = CSV.parse(described_class.new(pivot, 2026, WeatherPanel.new(cell, dates.first..dates.first,
      emergence_date: dates.first).days).to_csv.delete_prefix(CsvExport::BOM))
    expect(stored_only).to include(["Days: 2026-07-01 to 2026-07-01, one row each"])
  end
end

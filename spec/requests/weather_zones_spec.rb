require "rails_helper"

RSpec.describe "Weather zones (G.12)", type: :request do
  let(:user) { create(:user) }
  let(:group) { user.groups.first }
  let(:farm) { create(:farm, group:, name: "Hancock") }
  let!(:north) { create(:pivot, farm:, name: "North") }
  let!(:river) { create(:pivot, farm:, name: "River") }
  let(:cell) { north.weather_cell }

  before { sign_in user }

  around { |example| travel_to(Time.zone.local(2026, 7, 20, 9)) { example.run } }

  it "goes straight to the zone when there's only one" do
    get weather_zones_path
    expect(response).to redirect_to(weather_zone_path(cell))
  end

  it "lists the zones with their systems and the week ahead, and keeps their weather current" do
    away = create(:pivot, farm:, name: "Away", latitude: 45.5, longitude: -90.1)
    cell.weather_forecasts.create!(issued_at: 1.hour.ago, model: "m", payload: {days: [{date: "2026-07-20", tmax_f: 90}]})
    expect { get weather_zones_path }.to have_enqueued_job(WeatherUpdateJob).exactly(2).times
    expect_inertia.to render_component("WeatherZones/Index")
    zones = inertia.props[:zones]
    expect(zones.map { |zone| zone[:name] }).to eq(["Away", "North and River"])
    expect(zones.last[:pivots].map { |pivot| pivot[:name] }).to eq(%w[North River])
    expect(zones.last[:forecast].map { |day| day[:tmax_f] }).to eq([90])
    expect(zones.first).to include(id: away.weather_cell_id, forecast: [])
  end

  it "shows a zone's season of weather, the plantings degree days can count from, and the week ahead" do
    field = create(:field, pivot: north, name: "Home")
    create(:planting, field:, season_start: Date.new(2026, 5, 1), emergence_date: Date.new(2026, 5, 10),
      end_date: Date.new(2026, 9, 30))
    cell.weather_days.create!(date: Date.new(2026, 5, 1), et0_in: 0.2, tmax_f: 80, tmin_f: 60, model: "m", hours: 24,
      fetched_at: Time.current)
    cell.weather_forecasts.create!(issued_at: 1.hour.ago, model: "m", payload: {days: [{date: "2026-07-21", tmax_f: 88}]})

    get weather_zone_path(cell)
    expect_inertia.to render_component("WeatherZones/Show")
    props = inertia.props
    expect(props[:zone]).to include(name: "North and River", elevation_ft: nil)
    expect(props).to include(year: 2026, years: [2026], weather_from: "2026-01-01") # the whole year, whatever is planted
    expect(props[:weather].map { |day| [day[:date], day[:forecast]] }).to eq([["2026-05-01", false], ["2026-07-21", true]])
    expect(props[:plantings].sole).to include(label: match(/ on Home\z/), planted: "2026-05-01")
    expect(props[:forecast].map { |day| day[:date] }).to eq(["2026-07-21"])

    get weather_zone_path(cell, year: 2025)
    expect(inertia.props).to include(weather_from: "2025-01-01", weather: [], forecast: [], plantings: [])
  end

  it "downloads the zone's weather, and sends the pivot's old weather CSV link there" do
    get export_weather_zone_path(cell, year: 2026)
    expect(response.headers["Content-Disposition"]).to include("wisp-weather-north-and-river-2026.csv")
    rows = CSV.parse(response.body.delete_prefix(CsvExport::BOM))
    expect(rows.first).to eq(["WISP weather, North and River, 2026"])
    expect(rows).to include(["Irrigation systems: Hancock / #{north.label}; Hancock / #{river.label}"])

    get weather_pivot_path(north, year: 2026)
    expect(response).to redirect_to(export_weather_zone_path(cell, year: 2026))
  end

  it "links pages to their zone: a field's, and an ended planting's where its season ran" do
    field = create(:field, pivot: north)
    planting = create(:planting, field:, season_start: Date.new(2025, 5, 1), emergence_date: Date.new(2025, 5, 10),
      end_date: Date.new(2025, 9, 30))
    get field_path(field)
    expect(inertia.props[:weather_zone]).to eq({"id" => cell.id, "name" => "North and River"})

    old_cell = cell.id
    north.update_columns(weather_cell_id: create(:pivot, latitude: 45.5).weather_cell_id)
    get planting_path(planting)
    expect(inertia.props).to include(weather_zone: {"id" => old_cell, "name" => "River"}, forecast: [])
    get weather_zone_path(old_cell) # still reachable from the planting
    expect(inertia.props[:zone][:pivots].map { |pivot| pivot[:name] }).to eq(%w[North River])
  end
end

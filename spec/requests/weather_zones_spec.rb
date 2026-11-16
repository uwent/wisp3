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

  it "lists a lone zone too, rather than going straight to it (G.6)" do
    get weather_zones_path
    expect_inertia.to render_component("WeatherZones/Index")
    expect(inertia.props[:zones].sole).to include(id: cell.id, location: cell.location)
  end

  describe "addresses by location (G.6)" do
    it "is the cell's center to 2 decimals, and any point in the cell finds it" do
      expect(cell.location).to eq(format("%.2f,%.2f", cell.latitude, cell.longitude))
      expect(weather_zone_path(cell.location)).to eq("/weather/#{cell.location}")

      get weather_zone_path(cell.location)
      expect_inertia.to render_component("WeatherZones/Show")
      expect(inertia.props[:zone]).to include(location: cell.location)

      # The pivot's own coordinates, in the same cell, go to the cell's address, keeping the query
      get weather_zone_path("#{north.latitude},#{north.longitude}", year: 2025)
      expect(response).to redirect_to(weather_zone_path(cell.location, year: 2025))
      get export_weather_zone_path("#{north.latitude},#{north.longitude}")
      expect(response).to redirect_to(export_weather_zone_path(cell.location))
    end

    it "goes back to the list for a point outside the operation's zones, without making a cell" do
      expect { get weather_zone_path("46.5,-91.2") }.not_to change(WeatherCell, :count)
      expect(response).to redirect_to(weather_zones_path)
      expect(flash[:alert]).to eq("This operation has no weather zone at 46.5, -91.2.")
      get weather_zone_path("95,10")
      expect(response).to redirect_to(weather_zones_path)
      get export_weather_zone_path("46.5,-91.2")
      expect(response).to redirect_to(weather_zones_path)
    end

    it "sends the old addresses by id to the location" do
      get "/weather/#{cell.id}?year=2025"
      expect(response).to redirect_to(weather_zone_path(cell.location, year: 2025))
      expect(response).to have_http_status(:moved_permanently)
      get "/weather/#{cell.id}/export"
      expect(response).to redirect_to(export_weather_zone_path(cell.location))
    end
  end

  it "lists the zones with their systems and the week ahead, and keeps their weather current" do
    away = create(:pivot, farm:, name: "Away", latitude: 45.5, longitude: -90.1)
    create(:field, pivot: river, name: "Creek")
    create(:field, pivot: north, name: "Bend")
    create(:field, pivot: river, name: "apple")
    cell.weather_forecasts.create!(issued_at: 1.hour.ago, model: "m", payload: {days: [{date: "2026-07-20", tmax_f: 90}]})
    expect { get weather_zones_path }.to have_enqueued_job(WeatherUpdateJob).exactly(2).times
    expect_inertia.to render_component("WeatherZones/Index")
    zones = inertia.props[:zones]
    expect(zones.map { |zone| zone[:name] }).to eq(["Away", "North and River"])
    expect(zones.last[:pivots].map { |pivot| pivot[:name] }).to eq(%w[North River])
    expect(zones.last[:fields].map { |field| field[:name] }).to eq(%w[apple Bend Creek]) # by name, any case (G.6)
    expect(zones.last[:fields].first).to include(pivot_id: river.id, pivot: "River")
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

    get weather_zone_path(cell.location)
    expect_inertia.to render_component("WeatherZones/Show")
    props = inertia.props
    expect(props[:zone]).to include(name: "North and River", elevation_ft: nil)
    expect(props).to include(year: 2026, years: [2026], weather_from: "2026-01-01") # the whole year, whatever is planted
    expect(props[:weather].map { |day| [day[:date], day[:forecast]] }).to eq([["2026-05-01", false], ["2026-07-21", true]])
    expect(props[:plantings].sole).to include(label: match(/\AHome /), planted: "2026-05-01")
    expect(props[:forecast].map { |day| day[:date] }).to eq(["2026-07-21"])

    get weather_zone_path(cell.location, year: 2025)
    expect(inertia.props).to include(weather_from: "2025-01-01", weather: [], forecast: [], plantings: [])
  end

  it "downloads the zone's weather, and sends the pivot's old weather CSV link there" do
    get export_weather_zone_path(cell.location, year: 2026)
    expect(response.headers["Content-Disposition"]).to include("wisp-weather-north-and-river-2026.csv")
    rows = CSV.parse(response.body.delete_prefix(CsvExport::BOM))
    expect(rows.first).to eq(["WISP weather, North and River, 2026"])
    expect(rows).to include(["Irrigation systems: Hancock / #{north.label}; Hancock / #{river.label}"])

    get weather_pivot_path(north, year: 2026)
    expect(response).to redirect_to(export_weather_zone_path(cell.location, year: 2026))
  end

  it "links pages to their zone: a field's, and an ended planting's where its season ran" do
    field = create(:field, pivot: north)
    planting = create(:planting, field:, season_start: Date.new(2025, 5, 1), emergence_date: Date.new(2025, 5, 10),
      end_date: Date.new(2025, 9, 30))
    get field_path(field)
    expect(inertia.props[:weather_zone]).to eq({"id" => cell.id, "name" => "North and River", "location" => cell.location})

    old_cell = cell
    north.update_columns(weather_cell_id: create(:pivot, latitude: 45.5).weather_cell_id)
    get planting_path(planting)
    expect(inertia.props).to include(weather_zone: {"id" => old_cell.id, "name" => "River", "location" => old_cell.location}, forecast: [])
    get weather_zone_path(old_cell.location) # still reachable from the planting
    expect(inertia.props[:zone][:pivots].map { |pivot| pivot[:name] }).to eq(%w[North River])
  end
end

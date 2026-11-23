require "rails_helper"

RSpec.describe "Map", type: :request do
  let(:user) { create(:user) }
  let(:farm) { create(:farm, group: user.groups.first, name: "Hancock Sands") }
  let(:system) do
    create(:system, farm:, name: "North 160", latitude: 44.1335, longitude: -89.5213, radius_ft: 1300,
      arc_start_deg: 30, arc_end_deg: 300)
  end
  let(:field) { create(:field, system:, name: "North potatoes") }

  before do
    create(:planting, field:, season_start: Date.new(2026, 5, 1), emergence_date: Date.new(2026, 5, 20),
      end_date: Date.new(2026, 9, 15))
    (Date.new(2026, 5, 1)..Date.new(2026, 7, 19)).each do |date|
      system.weather_cell.weather_days.create!(date:, et0_in: 0.2, precip_in: (date.day == 15) ? 0.5 : 0.0,
        tmax_f: 85, tmin_f: 60, model: "ncep_nbm_conus", hours: 24, fetched_at: Time.current)
    end
    sign_in user
  end

  around { |example| travel_to(Time.zone.local(2026, 7, 20, 9)) { example.run } }

  it "gives each system its location, its weather zone and its fields' cards" do
    get map_path
    expect_inertia.to render_component("Map/Show")
    shown = inertia.props[:farms].sole[:systems].sole
    expect(shown).to include(id: system.id, name: "North 160", latitude: 44.1335, longitude: -89.5213, kind: "center",
      radius_ft: 1300, arc_start_deg: 30, arc_end_deg: 300, length_ft: nil, travel_ft: nil, travel_bearing_deg: nil)
    expect(shown[:weather_cell_id]).to eq(system.weather_cell_id)
    card = shown[:fields].sole
    expect(card).to include(id: field.id, name: "North potatoes")
    expect(card[:plantings].sole).to include(phase: "active")
  end

  it "gives the systems' weather zones their grid cell, last week and week ahead" do
    other = create(:system, farm:, name: "Next door", latitude: 44.134, longitude: -89.521)
    get map_path
    zone = inertia.props[:zones].sole
    cell = system.weather_cell
    expect(other.weather_cell_id).to eq(cell.id)
    expect(zone).to include(id: cell.id, location: cell.location, coordinates: "44.11°N, 89.59°W")
    grid = Weather::Grid.cell_for(cell.latitude, cell.longitude)
    expect(zone[:bounds]).to eq("north" => grid.lat_north, "south" => grid.lat_south, "west" => grid.lng_west, "east" => grid.lng_east)
    expect(zone[:bounds]["south"]).to be < 44.1335
    expect(zone[:weather][:past]).to include(days: 7, precip: 0.5, tmax: [85, 85], tmin: [60, 60])
    expect(zone[:weather][:past][:et0]).to be_within(1e-9).of(1.4)
    expect(zone[:weather][:ahead]).to be_nil # no forecast stored
    expect(zone[:forecast]).to eq([])
  end

  it "gives each system its fields' outlines" do
    outline = {"type" => "Polygon", "coordinates" => [[[-89.53, 44.13], [-89.52, 44.13], [-89.52, 44.14], [-89.53, 44.13]]]}
    field.update!(boundary: outline)
    create(:field, system:, name: "No outline")
    get map_path
    shown = inertia.props[:farms].sole[:systems].sole
    expect(shown[:outlines]).to eq([{"field_id" => field.id, "boundary" => outline}])
  end

  it "shows another season's plantings, and offers the seasons there are" do
    create(:planting, field:, season_start: Date.new(2025, 5, 1), emergence_date: Date.new(2025, 5, 20),
      end_date: Date.new(2025, 9, 15))
    get map_path
    expect(inertia.props).to include(year: 2026, years: [2026, 2025])

    new_field = create(:field, system:, name: "New this year")
    create(:planting, field: new_field, season_start: Date.new(2026, 8, 1), emergence_date: Date.new(2026, 8, 10),
      end_date: Date.new(2026, 10, 15))

    get map_path(year: 2025)
    expect(inertia.props[:year]).to eq(2025)
    cards = inertia.props[:farms].sole[:systems].sole[:fields].index_by { |card| card[:name] }
    plantings = cards.fetch("North potatoes")[:plantings]
    expect(plantings.map { |summary| [summary[:season_start], summary[:phase]] }).to eq([["2025-05-01", "ended"]])
    # A field planted only this year has nothing in 2025, not this year's planting
    expect(cards.fetch("New this year")[:plantings]).to eq([])

    get map_path(year: 1900)
    expect(inertia.props[:year]).to eq(2026)
  end
end

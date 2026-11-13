require "rails_helper"

# A field's outline page (PLAN.md Phase 8 G.10)
RSpec.describe "Field outlines", type: :request do
  let(:user) { create(:user) }
  let(:group) { user.groups.first }
  let(:pivot) { create(:pivot, farm: create(:farm, group:), radius_ft: 1300) }
  let(:sand) { create(:soil_type, name: "Sand") }
  let(:loam) { create(:soil_type, name: "Loam", field_capacity: 0.3, perm_wilting_pt: 0.12) }
  let(:field) { create(:field, pivot:, soil_type: sand, area_acres: 200) }
  # 222.34 acres
  let(:square) do
    {"type" => "Polygon", "coordinates" => [[[-89.35, 43.3], [-89.34, 43.3], [-89.34, 43.31], [-89.35, 43.31], [-89.35, 43.3]]]}
  end

  before { sign_in user }

  it "shows the field with its system, the group's other systems and outlined fields, and soil types" do
    other = create(:field, pivot: create(:pivot, farm: pivot.farm, name: "River"), boundary: square)
    create(:field, pivot: other.pivot) # no outline, not drawn
    get field_outline_path(field, from: "setup")
    expect_inertia.to render_component("Fields/Outline")
    expect(inertia.props[:field]).to include(id: field.id, boundary: nil, boundary_acres: nil)
    expect(inertia.props[:pivot]).to include("id" => pivot.id, "kind" => "center", "kind_name" => "Pivot", "radius_ft" => 1300)
    expect(inertia.props[:other_pivots].map { |p| p["name"] }).to eq(["River"])
    expect(inertia.props[:other_fields]).to eq([{"id" => other.id, "name" => other.name, "boundary" => square}])
    expect(inertia.props[:from]).to eq("setup")
  end

  it "saves an outline without changing the area, and back to the field page" do
    planting = create(:planting, field:)
    patch field_outline_path(field), params: {outline: {boundary: square.to_json}}
    expect(response).to redirect_to(field_path(field))
    expect(flash[:notice]).to eq("Saved the shape of #{field.name}")
    expect(field.reload.boundary).to eq(square)
    expect(field.area_acres).to eq(200)
    expect(planting.reload.area_acres).to eq(200)
  end

  it "uses the outline's acres and the survey's soil when asked, for seasons that haven't ended" do
    ended = create(:planting, field:, season_start: Date.new(2025, 4, 1), emergence_date: Date.new(2025, 5, 1),
      end_date: Date.new(2025, 9, 30))
    open = create(:planting, field:)
    travel_to(Date.new(2026, 6, 1)) do
      patch field_outline_path(field, from: "setup"),
        params: {outline: {boundary: square.to_json, area_acres: "222.34", soil_type_id: loam.id}}
    end
    expect(response).to redirect_to(setup_path)
    expect(field.reload).to have_attributes(area_acres: 222.34, soil_type: loam)
    expect(open.reload).to have_attributes(area_acres: 222.34, soil_type: loam)
    expect(ended.reload).to have_attributes(area_acres: 200, soil_type: sand)
  end

  it "keeps an outline saved under older limits while the field's other values change, but not a new one" do
    # 150 corners: allowed before G.14 part 7 lowered the limit to 100
    # (rounded as stored, so the page sending it back unchanged isn't a change)
    circle = (0...150).map do |i|
      angle = 2 * Math::PI * i / 150
      [(-89.4 + 0.001 * Math.cos(angle)).round(7), (43.3 + 0.001 * Math.sin(angle)).round(7)]
    end
    old = {"type" => "Polygon", "coordinates" => [circle + [circle.first]]}
    field.update_column(:boundary, old)
    patch field_outline_path(field), params: {outline: {boundary: old.to_json, area_acres: "190"}}
    expect(field.reload).to have_attributes(area_acres: 190, boundary: old)
    expect(field.update(name: "Renamed")).to be(true)

    redrawn = {"type" => "Polygon", "coordinates" => [circle.reverse + [circle.last]]}
    patch field_outline_path(field), params: {outline: {boundary: redrawn.to_json}}
    expect(field.reload.boundary).to eq(old)
  end

  it "removes the outline when sent blank" do
    field.update!(boundary: square)
    patch field_outline_path(field), params: {outline: {boundary: ""}}
    expect(field.reload.boundary).to be_nil
  end

  it "refuses an outline that isn't one, with the reason, changing nothing" do
    patch field_outline_path(field), params: {outline: {boundary: {type: "Point", coordinates: [-89, 43]}.to_json, area_acres: "5"}}
    expect(response).to redirect_to(field_outline_path(field))
    follow_redirect!
    expect(inertia.props[:errors]).to include("boundary" => ["must be a polygon"])
    expect(field.reload).to have_attributes(boundary: nil, area_acres: 200)
  end

  describe "a shape away from its system (G.14 part 7)" do
    let!(:open_season) { create(:planting, field:, end_date: Date.current + 30) }
    let!(:ended) do
      create(:planting, field:, season_start: Date.current.prev_year.beginning_of_year + 90,
        emergence_date: Date.current.prev_year.beginning_of_year + 120, end_date: Date.current.prev_year.beginning_of_year + 250)
    end

    it "sends the systems with their weather cells, the cell's edges and the open seasons' years" do
      other = create(:pivot, farm: pivot.farm, name: "Lane 3", kind: "traveler")
      get field_outline_path(field)
      expect(inertia.props[:pivot]).to include("weather_cell_id" => pivot.weather_cell_id)
      expect(inertia.props[:other_pivots].sole).to include("id" => other.id, "kind_name" => "Traveler",
        "weather_cell_id" => other.weather_cell_id)
      expect(inertia.props[:cell]["south"]).to be < pivot.latitude
      expect(inertia.props[:cell]["north"]).to be >= pivot.latitude
      expect(inertia.props[:open_years]).to eq([open_season.season_year])
    end

    it "moves the field to another system with the shape, its open season following" do
      other = create(:pivot, farm: pivot.farm, name: "Lane 3", kind: "traveler", latitude: 43.305, longitude: -89.345)
      patch field_outline_path(field), params: {outline: {boundary: square.to_json, pivot_id: other.id}}
      expect(flash[:notice]).to eq("Saved the shape of #{field.name} and moved it to Lane 3 (traveler)")
      expect(field.reload).to have_attributes(pivot: other, boundary: square)
      expect(open_season.reload).to have_attributes(pivot: other, weather_cell: other.weather_cell)
      expect(ended.reload.pivot).to eq(pivot)
    end

    it "keeps the field on its system when that's the one sent" do
      patch field_outline_path(field), params: {outline: {boundary: square.to_json, pivot_id: pivot.id}}
      expect(flash[:notice]).to eq("Saved the shape of #{field.name}")
      expect(field.reload.pivot).to eq(pivot)
    end

    it "makes a Location at the shape, named after the field, and moves the field to it" do
      patch field_outline_path(field), params: {outline: {boundary: square.to_json, new_location: "1",
                                                          latitude: "43.305", longitude: "-89.345"}}
      location = field.reload.pivot
      expect(location).to have_attributes(kind: "point", name: field.name, farm: pivot.farm, latitude: 43.305, longitude: -89.345)
      expect(flash[:notice]).to eq("Saved the shape of #{field.name} and moved it to #{field.name} (location)")
      expect(open_season.reload).to have_attributes(pivot: location, weather_cell: location.weather_cell)
      expect(ended.reload.pivot).to eq(pivot)
    end

    it "saves nothing when the Location can't be made" do
      patch field_outline_path(field), params: {outline: {boundary: square.to_json, new_location: "1", latitude: "", longitude: ""}},
        headers: {"HTTP_REFERER" => field_outline_url(field)}
      expect(field.reload).to have_attributes(pivot:, boundary: nil)
      expect(Pivot.where(kind: "point")).to be_empty
      follow_redirect!
      expect(inertia.props[:errors][:pivot_id].first).to start_with("couldn't be added as a Location")
    end
  end
end

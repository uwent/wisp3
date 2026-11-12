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
    expect(flash[:notice]).to eq("Saved the outline of #{field.name}")
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
end

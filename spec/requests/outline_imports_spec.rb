require "rails_helper"

# Field outlines for many fields from one file (PLAN.md Phase 8 G.10)
RSpec.describe "Outline imports", type: :request do
  let(:user) { create(:user) }
  let(:group) { user.groups.first }
  let(:farm) { create(:farm, group:, name: "Home") }
  let(:pivot) { create(:pivot, farm:, name: "North 160") }
  let(:sand) { create(:soil_type, name: "Sand") }
  let!(:field) { create(:field, pivot:, name: "Home North", area_acres: 200) }

  def square(west, south, size = 0.01)
    east, north = (west + size).round(7), (south + size).round(7)
    {"type" => "Polygon", "coordinates" => [[[west, south], [east, south], [east, north], [west, north], [west, south]]]}
  end

  before { sign_in user }

  it "lists the group's systems with their farm and shape, and its fields" do
    create(:field, pivot:, name: "Home South", boundary: square(-89.35, 43.3))
    get new_outline_import_path
    expect_inertia.to render_component("Setup/ImportOutlines")
    expect(inertia.props[:pivots].sole).to include("id" => pivot.id, "name" => "North 160", "farm" => "Home",
      "kind" => "center", "kind_name" => "Pivot")
    expect(inertia.props[:fields].map { |f| [f["name"], f["outlined"]] }).to eq([["Home North", false], ["Home South", true]])
  end

  it "outlines existing fields and adds new ones with the outline's acres, in one save" do
    rows = {outline_import: {use_area: "0", rows: [
      {boundary: square(-89.35, 43.3).to_json, field_id: field.id},
      {boundary: square(-89.33, 43.3).to_json, pivot_id: pivot.id, name: "River", soil_type_id: sand.id, area_acres: "222.34"}
    ]}}
    expect { post outline_import_path, params: rows }.to change(Field, :count).by(1)
    expect(response).to redirect_to(setup_path)
    expect(flash[:notice]).to eq("Saved 2 outlines (1 new field)")
    expect(field.reload).to have_attributes(boundary: square(-89.35, 43.3), area_acres: 200)
    expect(pivot.fields.find_by!(name: "River")).to have_attributes(soil_type: sand, area_acres: 222.34,
      boundary: square(-89.33, 43.3))
  end

  it "sets existing fields' area from their outlines when asked" do
    post outline_import_path, params: {outline_import: {use_area: "1", rows: [{boundary: square(-89.35, 43.3).to_json, field_id: field.id}]}}
    expect(flash[:notice]).to eq("Saved an outline")
    expect(field.reload.area_acres).to eq(222.34)
  end

  it "saves nothing when any row fails, with errors keyed by row" do
    post outline_import_path, params: {outline_import: {rows: [
      {boundary: square(-89.35, 43.3).to_json, field_id: field.id},
      {boundary: square(-89.33, 43.3).to_json, pivot_id: pivot.id, name: "", soil_type_id: sand.id, area_acres: "1"},
      {boundary: square(-89.31, 43.3).to_json, field_id: field.id}
    ]}}
    expect(response).to redirect_to(new_outline_import_path)
    follow_redirect!
    expect(inertia.props[:errors]).to include("rows.1.name" => ["can't be blank"], "rows.2.field_id" => ["is also in row 1"])
    expect(field.reload.boundary).to be_nil
    expect(pivot.fields.count).to eq(1)
  end

  it "asks for at least one shape" do
    post outline_import_path, params: {outline_import: {use_area: "0"}}
    follow_redirect!
    expect(inertia.props[:errors]).to include("rows" => "Choose at least one shape to save")
  end
end

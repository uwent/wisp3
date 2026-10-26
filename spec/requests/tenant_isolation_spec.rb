require "rails_helper"

# Every route that takes a group-owned record's ID must 404 for another group's record and leave it
# unchanged (PLAN.md §9 S1, the legacy app's worst bug)
RSpec.describe "Tenant isolation", type: :request do
  let(:user) { create(:user) }
  let(:outsider) { create(:user) }
  let(:their_farm) { create(:farm, group: outsider.groups.first) }
  let(:their_pivot) { create(:pivot, farm: their_farm) }
  let(:their_field) { create(:field, pivot: their_pivot) }
  let(:their_planting) { create(:planting, field: their_field) }
  let(:their_irrigation) { create(:pivot_irrigation, pivot: their_pivot) }
  let(:their_field_group) { create(:field_group, group: outsider.groups.first) }
  let(:my_farm) { create(:farm, group: user.groups.first) }
  let(:my_pivot) { create(:pivot, farm: my_farm) }
  let(:my_field) { create(:field, pivot: my_pivot) }

  before do
    sign_in user
    get root_path # Devise's test sign_in applies on the first request; a 404 wouldn't save the session
  end

  def expect_not_found
    expect(response).to have_http_status(:not_found)
  end

  it "hides other groups' farms" do
    patch farm_path(their_farm), params: {farm: {name: "Mine now"}}
    expect_not_found
    delete farm_path(their_farm)
    expect_not_found
    expect(their_farm.reload.name).not_to eq("Mine now")
  end

  it "hides other groups' pivots" do
    get pivot_path(their_pivot)
    expect_not_found
    get edit_pivot_path(their_pivot)
    expect_not_found
    patch pivot_path(their_pivot), params: {pivot: {name: "Mine now"}}
    expect_not_found
    delete pivot_path(their_pivot)
    expect_not_found
    expect(their_pivot.reload.name).not_to eq("Mine now")
  end

  it "won't create a pivot on, or move one to, another group's farm" do
    post pivots_path, params: {pivot: {farm_id: their_farm.id, name: "Sneaky", latitude: 44, longitude: -89}}
    expect_not_found
    patch pivot_path(my_pivot), params: {pivot: {farm_id: their_farm.id}}
    expect_not_found
    expect(my_pivot.reload.farm).to eq(my_farm)
  end

  it "hides other groups' fields" do
    get field_path(their_field)
    expect_not_found
    patch field_path(their_field), params: {field: {name: "Mine now"}}
    expect_not_found
    delete field_path(their_field)
    expect_not_found
    patch field_day_path(their_field, "2026-07-01"), params: {day: {rain_in: 1}}
    expect_not_found
    expect(their_field.reload.name).not_to eq("Mine now")
    expect(their_field.field_entries).to be_empty
  end

  it "won't create a field under, or move one to, another group's pivot" do
    post fields_path, params: {field: {pivot_id: their_pivot.id, name: "Sneaky", soil_type_id: my_field.soil_type_id}}
    expect_not_found
    patch field_path(my_field), params: {field: {pivot_id: their_pivot.id}}
    expect_not_found
    expect(my_field.reload.pivot).to eq(my_pivot)
  end

  it "won't record canopy on another group's planting through my field" do
    patch field_day_path(my_field, "2026-07-01"), params: {day: {canopy: 50}, planting_id: their_planting.id}
    expect_not_found
    expect(their_planting.canopy_observations).to be_empty
  end

  it "hides other groups' plantings" do
    post plantings_path, params: {planting: {field_id: their_field.id, plant_id: their_planting.plant_id}}
    expect_not_found
    patch planting_path(their_planting), params: {planting: {variety: "Mine now"}}
    expect_not_found
    get export_planting_path(their_planting)
    expect_not_found
    delete planting_path(their_planting)
    expect_not_found
    expect(their_planting.reload.variety).not_to eq("Mine now")
  end

  it "hides other groups' pivot weather and irrigation exports" do
    get weather_pivot_path(their_pivot)
    expect_not_found
    get pivot_irrigations_path(their_pivot)
    expect_not_found
  end

  it "leaves other groups' fields out of the season report" do
    create(:planting, field: their_field)
    create(:planting, field: my_field)
    get season_report_path(year: 2026)
    expect(response.body).to include(my_field.name)
    expect(response.body).not_to include(their_field.name)
  end

  it "hides other groups' pivot irrigation" do
    post pivot_irrigations_path(their_pivot), params: {pivot_irrigation: {date: "2026-07-02", inches: 1}}
    expect_not_found
    patch pivot_irrigation_path(their_pivot, their_irrigation), params: {pivot_irrigation: {inches: 9}}
    expect_not_found
    patch pivot_irrigation_path(my_pivot, their_irrigation), params: {pivot_irrigation: {inches: 9}}
    expect_not_found
    delete pivot_irrigation_path(my_pivot, their_irrigation)
    expect_not_found
    expect(their_irrigation.reload.inches).to eq(0.75)
  end

  it "hides other groups' field groups and won't add their fields to mine" do
    get field_group_path(their_field_group)
    expect_not_found
    patch field_group_path(their_field_group), params: {field_group: {name: "Mine now"}}
    expect_not_found
    patch field_group_day_path(their_field_group, "2026-07-01"), params: {day: {rain_in: 1}}
    expect_not_found
    delete field_group_path(their_field_group)
    expect_not_found

    post field_groups_path, params: {field_group: {name: "Mine", field_ids: [my_field.id, their_field.id]}}
    expect(user.groups.first.field_groups.sole.fields).to eq([my_field])
  end

  it "ignores other groups' pivots and fields in bulk daily entry" do
    patch daily_entry_path, params: {date: "2026-07-01", pivots: {their_pivot.id => {inches: 1}},
                                     fields: {their_field.id => {rain_in: 1}}}
    expect(their_pivot.pivot_irrigations).to be_empty
    expect(their_field.field_entries).to be_empty
  end

  it "won't apply my pivot's irrigation to another group's field" do
    post pivot_irrigations_path(my_pivot), params: {pivot_irrigation: {date: "2026-07-02", inches: 1, field_ids: [their_field.id]}}
    patch daily_entry_path, params: {date: "2026-07-03", pivots: {my_pivot.id => {inches: 1, field_ids: [their_field.id]}}}
    expect(my_pivot.pivot_irrigations).to be_empty
  end

  it "won't move another group's fields into my field group" do
    group = create(:field_group, group: user.groups.first, fields: [my_field])
    patch field_group_path(group), params: {field_group: {field_ids: [my_field.id, their_field.id]}}
    expect(group.reload.fields).to eq([my_field])
  end

  it "won't show another group's planting on my field's page" do
    their_planting
    get field_path(my_field, planting_id: their_planting.id)
    expect(response).to have_http_status(:ok)
    expect(inertia.props[:planting]).to be_nil
  end

  it "won't preselect another group's farm on the pivot form" do
    my_farm
    get new_pivot_path(farm_id: their_farm.id)
    expect(inertia.props[:pivot]["farm_id"]).to be_nil
    expect(inertia.props[:farms].pluck(:id)).to eq([my_farm.id])
  end

  it "copies only my group's plantings to the next season" do
    create(:planting, field: their_field, season_start: Date.new(2025, 4, 1), emergence_date: Date.new(2025, 5, 15),
      end_date: Date.new(2025, 9, 30))
    post season_copy_path(year: 2026)
    expect(their_field.plantings.in_season(2026)).to be_empty
  end

  it "won't use another group's farm in the guided setup" do
    post quick_setup_path, params: {setup: {farm_id: their_farm.id, pivot: {name: "P", latitude: 44, longitude: -89}}}
    expect_not_found
  end

  it "shows only the user's own records on the dashboard, setup and daily entry pages" do
    their_field
    my_field
    get root_path
    expect(inertia.props[:farms].flat_map { |farm| farm[:pivots].flat_map { |pivot| pivot[:fields].pluck(:id) } }).to eq([my_field.id])
    get setup_path
    expect(inertia.props[:farms].map { |farm| farm[:id] }).to eq([my_farm.id])
    get daily_entry_path
    expect(inertia.props[:farms].map { |farm| farm[:id] }).to eq([my_farm.id])
    get field_groups_path
    expect(inertia.props[:fields].map { |field| field[:id] }).to eq([my_field.id])
  end
end

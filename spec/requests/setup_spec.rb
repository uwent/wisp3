require "rails_helper"

RSpec.describe "Setup", type: :request do
  let(:user) { create(:user) }
  let(:group) { user.groups.first }
  let(:sand) { create(:soil_type, key: "sand", name: "Sand", field_capacity: 0.10, perm_wilting_pt: 0.04) }
  let(:potato) { create(:plant, key: "potato", name: "Potato", default_max_root_zone_depth: 16.0) }
  let(:farm) { create(:farm, group:, name: "Hancock") }
  let(:pivot) { create(:pivot, farm:, name: "North") }

  before { sign_in user }

  around { |example| travel_to(Date.new(2026, 7, 20)) { example.run } }

  describe "the setup page" do
    it "shows farms, pivots, fields and plantings, with reference data" do
      field = create(:field, pivot:, soil_type: sand)
      create(:planting, field:, plant: potato)
      get setup_path
      expect_inertia.to render_component("Setup/Show")
      farm_props = inertia.props[:farms].sole
      expect(farm_props[:pivots].sole[:fields].sole[:plantings].sole).to include(plant_name: "Potato", year: 2026)
      expect(inertia.props[:plants].map { |plant| plant[:name] }).to include("Potato")
      expect(inertia.props[:year]).to eq(2026)
    end

    it "updates the group's name and rainfall setting" do
      patch setup_path, params: {group: {name: "Sands Farms", use_model_precip: "false"}}
      expect(group.reload).to have_attributes(name: "Sands Farms", use_model_precip: false)
    end
  end

  describe "farms" do
    it "creates, renames and deletes a farm" do
      post farms_path, params: {farm: {name: "Plover"}}
      farm = group.farms.sole
      expect(farm.name).to eq("Plover")
      patch farm_path(farm), params: {farm: {name: "Plover River"}}
      expect(farm.reload.name).to eq("Plover River")
      delete farm_path(farm)
      expect(group.farms).to be_empty
    end

    it "sends validation errors back" do
      post farms_path, params: {farm: {name: ""}}
      follow_redirect!
      expect(inertia.props[:errors]).to include("name")
    end
  end

  describe "pivots" do
    it "creates a pivot at a location and assigns its weather cell" do
      post pivots_path, params: {pivot: {farm_id: farm.id, name: "South", latitude: 44.11, longitude: -89.54, radius_ft: 950,
                                         arc_start_deg: "", arc_end_deg: ""}}
      pivot = farm.pivots.sole
      expect(pivot).to have_attributes(name: "South", radius_ft: 950, arc_start_deg: nil)
      expect(pivot.weather_cell).to be_present
      expect(WeatherBackfillJob).to have_been_enqueued.with(pivot.weather_cell_id)
    end

    it "requires a location" do
      post pivots_path, params: {pivot: {farm_id: farm.id, name: "Nowhere"}}
      expect(response).to redirect_to(new_pivot_path(farm_id: farm.id))
      follow_redirect!
      expect(inertia.props[:errors]).to include("latitude", "longitude")
    end

    it "edits a pivot and moves it to another farm" do
      other = create(:farm, group:)
      get edit_pivot_path(pivot)
      expect(inertia.props[:pivot]).to include(name: "North")
      patch pivot_path(pivot), params: {pivot: {farm_id: other.id, name: "North 160", pump_capacity_gpm: 900}}
      expect(pivot.reload).to have_attributes(farm: other, name: "North 160", pump_capacity_gpm: 900)
    end

    it "shows other pivots on the map picker" do
      create(:pivot, farm:, name: "Neighbor")
      get new_pivot_path(farm_id: farm.id)
      expect_inertia.to render_component("Pivots/Form")
      expect(inertia.props[:other_pivots].map { |p| p["name"] }).to eq(["Neighbor"])
    end
  end

  describe "fields" do
    it "creates a field, overrides its soil values, and deletes it" do
      post fields_path, params: {field: {pivot_id: pivot.id, name: "North potatoes", area_acres: 70, soil_type_id: sand.id}}
      field = pivot.fields.sole
      patch field_path(field), params: {field: {field_capacity: 0.12, perm_wilting_pt: ""}}
      expect(field.reload).to have_attributes(field_capacity: 0.12, perm_wilting_pt: nil, effective_perm_wilting_pt: 0.04)
      delete field_path(field)
      expect(pivot.fields).to be_empty
    end

    it "rejects a wilting point above field capacity" do
      field = create(:field, pivot:, soil_type: sand)
      patch field_path(field), params: {field: {perm_wilting_pt: 0.2}}
      expect(field.reload.perm_wilting_pt).to be_nil
    end
  end

  describe "plantings" do
    let(:field) { create(:field, pivot:, soil_type: sand) }

    it "creates a planting with the crop's defaults for the season" do
      post plantings_path(year: 2027), params: {planting: {field_id: field.id, plant_id: potato.id, emergence_date: "2027-05-20"}}
      expect(field.plantings.sole).to have_attributes(season_start: Date.new(2027, 4, 1), emergence_date: Date.new(2027, 5, 20),
        end_date: Date.new(2027, 11, 30), max_root_zone_depth: 16.0, mad_frac: 0.5, et_method: "pct_cover")
    end

    it "refuses overlapping plantings on a field" do
      create(:planting, field:, plant: potato)
      post plantings_path(year: 2026), params: {planting: {field_id: field.id, plant_id: potato.id}}
      expect(field.plantings.count).to eq(1)
    end

    it "updates and deletes a planting" do
      planting = create(:planting, field:, plant: potato)
      patch planting_path(planting), params: {planting: {variety: " Russet ", target_ad_pct: 40, et_method: "lai"}}
      expect(planting.reload).to have_attributes(variety: "Russet", target_ad_pct: 40, et_method: "lai")
      delete planting_path(planting)
      expect(field.plantings).to be_empty
    end

    it "exports the season as CSV" do
      planting = create(:planting, field:, plant: potato, season_start: Date.new(2026, 7, 1))
      field.field_entries.create!(date: Date.new(2026, 7, 3), rain_in: 0.5)
      get export_planting_path(planting)
      expect(response.media_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"]).to include("wisp-field-")
      rows = CSV.parse(response.body)
      header = rows.index { |row| row.first == "Date" }
      expect(rows[header]).to include("Reference ET (in)", "AD (in)", "Rain source", "Deep drainage (in)")
      expect(rows[header + 3]).to include("2026-07-03", "0.5000", "entered")
      expect(rows.last.first).to eq("Totals")
    end
  end

  describe "guided first-run setup" do
    let(:corn) { create(:plant, :field_corn) }

    it "creates a farm, a pivot and its fields with this season's crops in one go" do
      get new_quick_setup_path
      expect_inertia.to render_component("Setup/Start")

      post quick_setup_path, params: {setup: {
        farm: {name: "Hancock Sands"},
        pivot: {name: "North 160", latitude: 44.1335, longitude: -89.5213, radius_ft: 1300},
        fields: {
          "0" => {name: "North potatoes", area_acres: 70, soil_type_id: sand.id, plant_id: potato.id, emergence_date: "2026-05-20"},
          "1" => {name: "North corn", area_acres: 55, soil_type_id: sand.id, plant_id: corn.id}
        }
      }}
      expect(response).to redirect_to(root_path)
      pivot = group.farms.sole.pivots.sole
      expect(pivot.fields.map(&:name)).to eq(["North corn", "North potatoes"])
      expect(pivot.fields.flat_map(&:plantings).map { |p| [p.plant.name, p.emergence_date] })
        .to contain_exactly(["Field Corn", Date.new(2026, 5, 1)], ["Potato", Date.new(2026, 5, 20)])
    end

    it "saves nothing and reports every problem by input" do
      post quick_setup_path, params: {setup: {
        farm: {name: "Hancock"},
        pivot: {name: "North", latitude: 44.1, longitude: -89.5},
        fields: {"0" => {name: "", soil_type_id: sand.id, plant_id: potato.id}, "1" => {name: "B", soil_type_id: sand.id}}
      }}
      follow_redirect!
      expect(inertia.props[:errors]).to include("fields.0.name", "fields.1.plant_id")
      expect(group.farms).to be_empty
    end

    it "creates a pivot without fields, skipping blank rows, and points to setup to add them" do
      post quick_setup_path, params: {setup: {farm: {name: "Hancock"}, pivot: {name: "North", latitude: 44.1, longitude: -89.5},
                                              fields: {"0" => {name: "", area_acres: "", soil_type_id: sand.id, plant_id: "", emergence_date: ""}}}}
      expect(response).to redirect_to(setup_path)
      expect(flash[:notice]).to include("Add its fields")
      expect(group.farms.sole.pivots.sole.fields).to be_empty
    end

    it "reports errors by each row's own index when an earlier row is blank" do
      post quick_setup_path, params: {setup: {farm: {name: "Hancock"}, pivot: {name: "North", latitude: 44.1, longitude: -89.5},
                                              fields: {"0" => {name: "", soil_type_id: sand.id}, "1" => {name: "B", soil_type_id: sand.id}}}}
      follow_redirect!
      expect(inertia.props[:errors].keys).to eq(["fields.1.plant_id"])
      expect(group.farms).to be_empty
    end

    it "adds to an existing farm" do
      post quick_setup_path, params: {setup: {farm_id: farm.id, pivot: {name: "East", latitude: 44.1, longitude: -89.5},
                                              fields: {"0" => {name: "East", soil_type_id: sand.id, plant_id: potato.id}}}}
      expect(farm.pivots.sole.fields.sole.name).to eq("East")
    end
  end

  describe "copying last season" do
    it "copies each field's plantings forward a year" do
      field = create(:field, pivot:, soil_type: sand)
      create(:planting, field:, plant: potato, season_start: Date.new(2025, 4, 1), emergence_date: Date.new(2025, 5, 18),
        end_date: Date.new(2025, 9, 20), target_ad_pct: 40)
      post season_copy_path(year: 2026)
      expect(response).to redirect_to(setup_path(year: 2026))
      expect(field.plantings.in_season(2026).sole).to have_attributes(emergence_date: Date.new(2026, 5, 18),
        end_date: Date.new(2026, 9, 20), target_ad_pct: 40)

      post season_copy_path(year: 2026)
      expect(field.plantings.in_season(2026).count).to eq(1)
      expect(flash[:notice]).to start_with("Nothing to copy")
    end

    it "reports plantings it couldn't copy" do
      field = create(:field, pivot:, name: "West", soil_type: sand)
      # A season running into the next year: its copy would overlap it
      create(:planting, field:, plant: potato, season_start: Date.new(2025, 4, 1), emergence_date: Date.new(2025, 5, 15),
        end_date: Date.new(2026, 5, 1))
      post season_copy_path(year: 2026)
      expect(field.plantings.in_season(2026)).to be_empty
      expect(flash[:alert]).to start_with("Couldn't copy Potato on West (")
      expect(flash[:notice]).to be_nil
    end
  end
end

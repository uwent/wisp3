require "rails_helper"

# Every route that takes a group-owned record's ID must 404 for another group's record and leave it
# unchanged (S1, the legacy app's worst bug)
RSpec.describe "Tenant isolation", type: :request do
  let(:user) { create(:user) }
  let(:outsider) { create(:user) }
  let(:their_farm) { create(:farm, group: outsider.groups.first) }
  let(:their_system) { create(:system, farm: their_farm) }
  let(:their_field) { create(:field, system: their_system) }
  let(:their_planting) { create(:planting, field: their_field) }
  let(:my_farm) { create(:farm, group: user.groups.first) }
  let(:my_system) { create(:system, farm: my_farm) }
  let(:my_field) { create(:field, system: my_system) }

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
    expect(their_farm.reload.name).not_to eq("Mine now") # still there, unchanged
  end

  it "hides other groups' systems" do
    get system_path(their_system)
    expect_not_found
    get edit_system_path(their_system)
    expect_not_found
    get new_system_path(copy_of: their_system.id)
    expect_not_found
    patch system_path(their_system), params: {system: {name: "Mine now"}}
    expect_not_found
    delete system_path(their_system)
    expect_not_found
    patch equipment_system_path(their_system), params: {system: {pump_capacity_gpm: 999}}
    expect_not_found
    expect(their_system.reload.name).not_to eq("Mine now")
    expect(their_system.pump_capacity_gpm).not_to eq(999)
  end

  it "won't create a system on, or move one to, another group's farm" do
    post systems_path, params: {system: {farm_id: their_farm.id, name: "Sneaky", latitude: 44, longitude: -89}}
    expect_not_found
    patch system_path(my_system), params: {system: {farm_id: their_farm.id}}
    expect_not_found
    expect(my_system.reload.farm).to eq(my_farm)
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

  it "won't create a field under, or move one to, another group's system" do
    post fields_path, params: {field: {system_id: their_system.id, name: "Sneaky", soil_type_id: my_field.soil_type_id}}
    expect_not_found
    patch field_path(my_field), params: {field: {system_id: their_system.id}}
    expect_not_found
    expect(my_field.reload.system).to eq(my_system)
  end

  it "won't record canopy on another group's planting through my field" do
    patch field_day_path(my_field, "2026-07-01"), params: {day: {canopy: 50}, planting_id: their_planting.id}
    expect_not_found
    expect(their_planting.canopy_observations).to be_empty
  end

  it "won't record another group's part-field planting's own entries through my field" do
    their_plot = create(:planting, field: create(:field, system: their_system), partial: true, area_acres: 1)
    patch field_day_path(my_field, "2026-07-01"), params: {day: {irrigation_in: 0.5}, planting_id: their_plot.id}
    expect_not_found
    expect(their_plot.planting_entries).to be_empty
  end

  it "hides other groups' field outlines" do
    square = {type: "Polygon", coordinates: [[[-89.35, 43.3], [-89.34, 43.3], [-89.34, 43.31], [-89.35, 43.31], [-89.35, 43.3]]]}
    get field_outline_path(their_field)
    expect_not_found
    patch field_outline_path(their_field), params: {outline: {boundary: square.to_json}}
    expect_not_found
    expect(their_field.reload.boundary).to be_nil
  end

  it "won't import outlines onto another group's fields or systems" do
    square = {type: "Polygon", coordinates: [[[-89.35, 43.3], [-89.34, 43.3], [-89.34, 43.31], [-89.35, 43.3]]]}.to_json
    post outline_import_path, params: {outline_import: {rows: [{boundary: square, field_id: their_field.id}]}}
    expect_not_found
    expect(their_field.reload.boundary).to be_nil
    post outline_import_path, params: {outline_import: {rows: [{boundary: square, system_id: their_system.id, name: "Sneaky",
                                                                soil_type_id: their_field.soil_type_id, area_acres: "5"}]}}
    expect_not_found
    expect(their_system.fields.where(name: "Sneaky")).to be_empty
    my_system
    get new_outline_import_path
    expect(inertia.props[:systems].map { |p| p["id"] }).to eq([my_system.id])
    expect(inertia.props[:fields]).to be_empty
  end

  it "won't move a field to another group's system from its shape page" do
    square = {type: "Polygon", coordinates: [[[-89.35, 43.3], [-89.34, 43.3], [-89.34, 43.31], [-89.35, 43.31], [-89.35, 43.3]]]}
    patch field_outline_path(my_field), params: {outline: {boundary: square.to_json, system_id: their_system.id}}
    expect_not_found
    expect(my_field.reload).to have_attributes(system: my_system, boundary: nil)
  end

  it "shows only my group's other fields and systems on a field's outline page" do
    their_field.update!(boundary: {type: "Polygon", coordinates: [[[-89.35, 43.3], [-89.34, 43.3], [-89.34, 43.31], [-89.35, 43.3]]]})
    their_system
    get field_outline_path(my_field)
    expect(inertia.props[:other_fields]).to be_empty
    expect(inertia.props[:other_systems]).to be_empty
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

  it "hides other groups' weather zones and irrigation exports" do
    get weather_system_path(their_system)
    expect_not_found
    get "/weather/#{their_system.weather_cell_id}"
    expect_not_found
    get "/weather/#{their_system.weather_cell_id}/export"
    expect_not_found
    # By location, their cell is a place this operation has no zone
    get weather_zone_path(their_system.weather_cell.location)
    expect(response).to redirect_to(weather_zones_path)
    get export_weather_zone_path(their_system.weather_cell.location)
    expect(response).to redirect_to(weather_zones_path)
    get system_irrigations_path(their_system)
    expect_not_found
  end

  it "leaves other groups' fields out of the season report" do
    create(:planting, field: their_field)
    create(:planting, field: my_field)
    get season_report_path(year: 2026)
    expect(response.body).to include(my_field.name)
    expect(response.body).not_to include(their_field.name)
  end

  it "hides other groups' irrigation systems' irrigation" do
    their_field.field_entries.create!(date: Date.new(2026, 7, 2), irrigation_in: 0.75)
    post system_irrigations_path(their_system), params: {irrigation: {date: "2026-07-02", fields: {their_field.id => "9"}}}
    expect_not_found
    delete system_irrigation_path(their_system, "2026-07-02")
    expect_not_found
    post system_irrigations_path(their_system), params: {irrigation: {date: "2026-07-03", from: "2026-07-02", fields: {their_field.id => "9"}}}
    expect_not_found
    expect(their_field.field_entries.sole).to have_attributes(date: Date.new(2026, 7, 2), irrigation_in: 0.75)
  end

  it "ignores other groups' fields in bulk daily entry" do
    patch daily_entry_path, params: {date: "2026-07-01", fields: {their_field.id => {rain_in: 1, irrigation_in: 1}}}
    expect(response).to redirect_to(daily_entry_path(date: "2026-07-01"))
    expect(their_field.field_entries).to be_empty
  end

  it "ignores other groups' plantings and canopy readings in bulk daily entry" do
    plot = create(:planting, field: their_field, partial: true, area_acres: 0.5)
    patch daily_entry_path, params: {date: "2026-07-01", plantings: {plot.id => {irrigation_in: 1}},
                                     canopy: {plot.id => 40}}
    expect(plot.planting_entries).to be_empty
    expect(plot.canopy_observations).to be_empty
  end

  it "ignores other groups' fields in daily entry's week" do
    day = {fields: {their_field.id => {rain_in: 1, irrigation_in: 1}}}
    patch daily_entry_week_path, params: {date: "2026-07-07", days: {"2026-07-01" => day}}
    expect(response).to redirect_to(daily_entry_week_path(date: "2026-07-07"))
    expect(their_field.field_entries).to be_empty
  end

  it "won't write another group's field through my system's irrigation (it isn't on my system)" do
    my_field
    post system_irrigations_path(my_system), params: {irrigation: {date: "2026-07-02", fields: {their_field.id => "2"}}}
    expect(response).to redirect_to(system_path(my_system))
    expect(their_field.field_entries).to be_empty

    their_field.field_entries.create!(date: Date.new(2026, 7, 3), irrigation_in: 0.75)
    post system_irrigations_path(my_system), params: {irrigation: {date: "2026-07-04", from: "2026-07-03", fields: {}}}
    delete system_irrigation_path(my_system, "2026-07-03")
    expect(their_field.field_entries.sole.irrigation_in).to eq(0.75)
  end

  it "won't show another group's planting on my field's page, or its own page" do
    their_planting
    mine = create(:planting, field: my_field)
    get field_path(my_field, planting_id: mine.id)
    expect(response).to redirect_to(planting_path(mine)) # the parameter picks a planting of the field's
    get field_path(my_field, planting_id: their_planting.id)
    expect(response).to have_http_status(:ok)
    expect(inertia.props[:planting]).to be_nil
    get planting_path(their_planting)
    expect(response).to have_http_status(:not_found)
  end

  it "won't add or remove cuttings on another group's planting" do
    their_planting.update!(plant: create(:plant, key: "alfalfa"), canopy_curve_key: nil)
    cutting = their_planting.canopy_cuttings.create!(date: their_planting.emergence_date + 30)
    get root_path
    post planting_cuttings_path(their_planting), params: {cutting: {date: (their_planting.emergence_date + 40).iso8601}}
    expect(response).to have_http_status(:not_found)
    delete planting_cutting_path(their_planting, cutting)
    expect(response).to have_http_status(:not_found)
    expect(their_planting.canopy_cuttings.count).to eq(1)
  end

  it "won't let Replace end another group's planting" do
    their_planting
    post plantings_path, params: {planting: {field_id: their_planting.field_id, plant_id: their_planting.plant_id,
                                             season_start: their_planting.season_start + 30, emergence_date: their_planting.season_start + 40,
                                             end_date: their_planting.end_date}, replace: "1"}
    expect(response).to have_http_status(:not_found)
    expect(their_planting.reload.end_date).to eq(their_planting.end_date)
  end

  it "won't preselect another group's farm on the system form" do
    my_farm
    get new_system_path(farm_id: their_farm.id)
    expect(inertia.props[:system]["farm_id"]).to be_nil
    expect(inertia.props[:farms].pluck(:id)).to eq([my_farm.id])
  end

  it "copies only my group's plantings to the next season" do
    create(:planting, field: their_field, season_start: Date.new(2025, 4, 1), emergence_date: Date.new(2025, 5, 15),
      end_date: Date.new(2025, 9, 30))
    post season_copy_path(year: 2026)
    expect(their_field.plantings.where(season_start: Date.new(2026).all_year)).to be_empty
  end

  it "won't use another group's farm in the guided setup" do
    post quick_setup_path, params: {setup: {farm_id: their_farm.id, system: {name: "P", latitude: 44, longitude: -89}}}
    expect_not_found
    expect(their_farm.systems).to be_empty
  end

  it "won't put my system in another group's irrigation group" do
    theirs = create(:irrigation_group, farm: their_farm)
    patch system_path(my_system), params: {system: {name: "Renamed", irrigation_group_id: theirs.id}}
    expect(my_system.reload).to have_attributes(irrigation_group_id: nil)
    expect(theirs.systems).to be_empty

    mine = create(:irrigation_group, farm: my_farm)
    patch system_path(my_system), params: {system: {irrigation_group_id: mine.id}}
    expect(my_system.reload.irrigation_group).to eq(mine)
  end

  it "shows a weather zone shared with another group's systems with only my own" do
    their_system.update!(name: "Their pivot", latitude: my_system.latitude, longitude: my_system.longitude)
    their_field.update!(name: "Their field")
    create(:planting, field: their_field)
    create(:planting, field: my_field)
    expect(their_system.reload.weather_cell).to eq(my_system.weather_cell)

    [weather_zones_path, weather_zone_path(my_system.weather_cell.location), export_weather_zone_path(my_system.weather_cell.location)].each do |path|
      get path
      expect(response).to have_http_status(:ok), path
      expect(response.body).to include(my_system.name), path
      expect(response.body).not_to include("Their pivot"), path
      expect(response.body).not_to include("Their field"), path
    end
  end

  it "lists only my systems whose weather is updating" do
    [my_system, their_system].each { |system| Rails.cache.write(WeatherUpdateJob.updating_key(system.weather_cell_id), true) }
    get weather_updates_path
    expect(response.parsed_body).to eq("system_ids" => [my_system.id])
  end

  it "shows only the user's own records on the dashboard, map, setup and daily entry pages" do
    their_field
    my_field
    get root_path
    expect(inertia.props[:farms].flat_map { |farm| farm[:systems].flat_map { |system| system[:fields].pluck(:id) } }).to eq([my_field.id])
    get map_path
    expect(inertia.props[:farms].flat_map { |farm| farm[:systems].pluck(:id) }).to eq([my_system.id])
    get setup_path
    expect(inertia.props[:farms].map { |farm| farm[:id] }).to eq([my_farm.id])
    get daily_entry_path
    expect(inertia.props[:farms].map { |farm| farm[:id] }).to eq([my_farm.id])
    [my_field, their_field].each do |field|
      create(:planting, field:, season_start: Date.current - 30, emergence_date: Date.current - 20, end_date: Date.current + 30)
    end
    get daily_entry_week_path
    expect(inertia.props[:farms].map { |farm| farm[:id] }).to eq([my_farm.id])
  end
end

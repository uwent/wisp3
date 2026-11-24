require "rails_helper"

# The same crop on several fields. A new whole-field planting's form can also plant it on
# the system's other fields (also_field_ids), each an independent planting on its own field's soil,
# area and weather cell, all saved or none.
RSpec.describe "Planting the same crop on several fields", type: :request do
  let(:user) { create(:user) }
  let(:group) { user.groups.first }
  let(:system) { create(:system, farm: create(:farm, group:)) }
  let(:sand) { create(:soil_type, name: "Sand", field_capacity: 0.12, perm_wilting_pt: 0.04) }
  let(:loam) { create(:soil_type, name: "Loam", field_capacity: 0.3, perm_wilting_pt: 0.12) }
  let(:north) { create(:field, system:, name: "North 40", soil_type: sand, area_acres: 40) }
  let(:east) { create(:field, system:, name: "East 40", soil_type: loam, area_acres: 35, field_capacity: 0.28) }
  let(:west) { create(:field, system:, name: "West 40", soil_type: loam, area_acres: 38) }
  let(:corn) { create(:plant, name: "Corn") }
  let(:values) do
    {field_id: north.id, plant_id: corn.id, variety: "P1185", season_start: "2026-04-20", emergence_date: "2026-05-05",
     end_date: "2026-09-25", max_root_zone_depth: 30, mad_frac: 0.4, target_ad_pct: 60, initial_moisture_pct: 90,
     notes: "North only"}
  end

  before { sign_in user }

  def plant_on(*fields, planting: {}, **params)
    post plantings_path(year: 2026), params: {planting: values.merge(planting), also_field_ids: fields.map(&:id), **params},
      headers: {"HTTP_REFERER" => setup_url(year: 2026)}
  end

  it "makes the same planting on each field, with that field's soil, area and weather cell" do
    plant_on(east, west)

    expect(flash[:notice]).to eq("Added Corn on North 40 and 2 other fields")
    original = north.plantings.sole
    [east, west].each do |field|
      copy = field.plantings.sole
      expect(copy).to have_attributes(original.attributes.slice(*%w[plant_id variety season_start emergence_date end_date
        max_root_zone_depth mad_frac et_method canopy_interpolation target_ad_pct initial_moisture_pct]))
      expect(copy).to have_attributes(soil_type_id: loam.id, field_capacity: field.field_capacity, perm_wilting_pt: nil,
        area_acres: field.area_acres, partial: false, own_soil: false, system_id: system.id,
        weather_cell_id: system.weather_cell_id, notes: nil, created_by_id: user.id)
    end
    expect(original).to have_attributes(soil_type_id: sand.id, area_acres: 40, notes: "North only")
  end

  it "names the one other field in the notice, and fills in the crop's defaults on each" do
    plant_on(east, planting: {end_date: "", max_root_zone_depth: "", variety: ""})

    expect(flash[:notice]).to eq("Added Corn on North 40 and East 40")
    expect(east.plantings.sole).to have_attributes(end_date: north.plantings.sole.end_date,
      max_root_zone_depth: corn.default_max_root_zone_depth, variety: nil)
  end

  it "doesn't copy a soil override given for the original" do
    plant_on(east, planting: {soil_type_id: loam.id, field_capacity: 0.33, area_acres: 12})
    expect(east.plantings.sole).to have_attributes(soil_type_id: loam.id, field_capacity: 0.28, area_acres: 35)
  end

  it "saves none when one field has a planting on those dates, naming it" do
    create(:planting, field: west, plant: create(:plant, name: "Soybean"))
    plant_on(east, west)

    expect(Planting.where(field: [north, east]).count).to eq(0)
    expect(west.plantings.count).to eq(1)
    follow_redirect!
    expect(inertia.props[:errors]).to eq("also.#{west.id}.season_start" => ["West 40: overlaps its Soybean planting"])
  end

  it "plants on a field growing only plots, whose plots stay (D19)" do
    create(:planting, field: west, plant: create(:plant, name: "Soybean"), partial: true, area_acres: 1)
    plant_on(west)

    expect(west.plantings.count).to eq(2)
    expect(west.plantings.where(partial: false).sole.plant).to eq(corn)
  end

  it "replaces only on the original's field, and undoes that too when a copy can't be saved" do
    early = create(:planting, field: north, season_start: Date.new(2026, 3, 1), emergence_date: Date.new(2026, 3, 10),
      end_date: Date.new(2026, 9, 30))
    other = create(:planting, field: west, season_start: Date.new(2026, 3, 1), emergence_date: Date.new(2026, 3, 10),
      end_date: Date.new(2026, 9, 30))
    plant_on(east, west, replace: "1")
    expect(early.reload.end_date).to eq(Date.new(2026, 9, 30))
    expect(other.reload.end_date).to eq(Date.new(2026, 9, 30))
    expect(Planting.count).to eq(2)

    plant_on(east, replace: "1")
    expect(early.reload.end_date).to eq(Date.new(2026, 4, 19))
    expect(north.plantings.count).to eq(2)
    expect(east.plantings.count).to eq(1)
  end

  it "ignores the original's own field, and makes no copies of part of a field" do
    plant_on(north)
    expect(north.plantings.count).to eq(1)
    expect(flash[:notice]).to eq("Added Corn on North 40")

    plant_on(east, planting: {partial: "true", area_acres: 2, season_start: "2026-10-01", emergence_date: "2026-10-02",
                              end_date: "2026-11-20"})
    expect(north.plantings.count).to eq(2)
    expect(east.plantings).to be_empty
  end

  it "makes no copies when a planting is edited" do
    planting = create(:planting, field: north, plant: corn)
    patch planting_path(planting), params: {planting: {variety: "Changed"}, also_field_ids: [east.id]}
    expect(planting.reload.variety).to eq("Changed")
    expect(east.plantings).to be_empty
  end

  it "takes the fields as an indexed list too" do
    post plantings_path(year: 2026), params: {planting: values, also_field_ids: {"0" => east.id, "1" => ""}}
    expect(east.plantings.count).to eq(1)
  end

  it "refuses another group's field, saving nothing" do
    get setup_path # Devise's sign_in takes effect on a normal request first
    theirs = create(:field)
    plant_on(east, theirs)

    expect(response).to have_http_status(:not_found)
    expect(Planting.count).to eq(0)
  end
end

require "rails_helper"

RSpec.describe "Field status, daily entry and field groups", type: :request do
  let(:user) { create(:user) }
  let(:group) { user.groups.first }
  let(:farm) { create(:farm, group:) }
  let(:pivot) { create(:pivot, farm:, pump_capacity_gpm: 900) }
  let(:field) { create(:field, pivot:, name: "North potatoes", area_acres: 60) }
  let!(:planting) do
    create(:planting, field:, season_start: Date.new(2026, 7, 1), emergence_date: Date.new(2026, 7, 1),
      end_date: Date.new(2026, 9, 30))
  end

  before do
    sign_in user
    (Date.new(2026, 7, 1)..Date.new(2026, 7, 19)).each do |date|
      pivot.weather_cell.weather_days.create!(date:, et0_in: 0.2, precip_in: (date.day == 5) ? 0.4 : 0.0, tmax_f: 85,
        tmin_f: 60, model: "ncep_nbm_conus", hours: 24, fetched_at: Time.current)
    end
  end

  around { |example| travel_to(Time.zone.local(2026, 7, 20, 9)) { example.run } }

  describe "the field page" do
    it "shows the season's balance, summary and weather" do
      pivot.weather_cell.weather_forecasts.create!(issued_at: 1.hour.ago, model: "ncep_nbm_conus",
        payload: {days: [{date: "2026-07-20", tmax_f: 90, tmin_f: 70}, {date: "2026-07-21", tmax_f: 88, tmin_f: 66}]})

      get field_path(field)
      expect_inertia.to render_component("Fields/Show")
      props = inertia.props
      expect(props[:planting][:id]).to eq(planting.id)
      expect(props[:days].size).to eq(20) # Jul 1 through today
      expect(props[:days][4]).to include(date: "2026-07-05", rain: 0.4, rain_source: "model", et0: 0.2)
      expect(props[:summary]).to include(phase: "active", date: "2026-07-20", ad_max: 1.2) # 0.5 × (0.15 − 0.05) × 24 in
      expect(props[:summary][:totals]).to include(rain: 0.4)
      expect(props[:weather].map { |day| [day[:date], day[:forecast]] }.last(2))
        .to eq([["2026-07-20", true], ["2026-07-21", true]])
    end

    it "shows a pivot's irrigation as from the pivot, and the pivot amount under a field's override" do
      pivot.pivot_irrigations.create!(date: Date.new(2026, 7, 10), inches: 0.8)
      field.field_entries.create!(date: Date.new(2026, 7, 10), irrigation_in: 0.5)
      pivot.pivot_irrigations.create!(date: Date.new(2026, 7, 12), run_hours: 10)

      get field_path(field)
      days = inertia.props[:days].index_by { |day| day[:date] }
      expect(days["2026-07-10"]).to include(irrigation: 0.5, irrigation_source: "entered", pivot_inches: 0.8)
      expect(days["2026-07-12"]).to include(irrigation_source: "pivot")
      expect(days["2026-07-12"][:irrigation]).to be_within(0.001).of(900 * 10 * 60 / (27_154.0 * 60))
    end

    it "picks another season's planting" do
      older = create(:planting, field:, season_start: Date.new(2025, 4, 1), emergence_date: Date.new(2025, 5, 1),
        end_date: Date.new(2025, 9, 1))
      get field_path(field, planting_id: older.id)
      expect(inertia.props[:summary]).to include(phase: "ended", date: "2025-09-01")
    end

    it "handles a field with no planting" do
      bare = create(:field, pivot:)
      get field_path(bare)
      expect(inertia.props).to include(planting: nil, summary: nil, days: [])
    end
  end

  describe "editing a day" do
    let(:url) { field_day_path(field, "2026-07-08") }

    it "records rain, irrigation, a moisture reading and notes, and clears them" do
      patch url, params: {day: {rain_in: 0.0, irrigation_in: 0.6, notes: " Gauge "}, planting_id: planting.id}
      expect(field.field_entries.sole).to have_attributes(rain_in: 0.0, irrigation_in: 0.6, soil_moisture_pct: nil, notes: "Gauge")

      patch url, params: {day: {soil_moisture_pct: 11}, planting_id: planting.id}
      expect(field.field_entries.sole).to have_attributes(rain_in: 0.0, soil_moisture_pct: 11)

      patch url, params: {day: {rain_in: nil, irrigation_in: nil, soil_moisture_pct: nil, notes: ""}}, as: :json
      expect(field.field_entries).to be_empty
    end

    it "records the planting's canopy reading as percent cover or LAI" do
      patch url, params: {day: {canopy: 35}, planting_id: planting.id}
      expect(planting.canopy_observations.sole).to have_attributes(date: Date.new(2026, 7, 8), pct_cover: 35, lai: nil)

      planting.update!(et_method: "lai")
      patch url, params: {day: {canopy: 1.5}, planting_id: planting.id}
      expect(planting.canopy_observations.sole).to have_attributes(pct_cover: nil, lai: 1.5)

      patch url, params: {day: {canopy: ""}, planting_id: planting.id}
      expect(planting.canopy_observations).to be_empty
    end

    it "rejects bad values without saving any of the day" do
      patch url, params: {day: {rain_in: -1, canopy: 150}, planting_id: planting.id}, headers: {"HTTP_REFERER" => field_path(field)}
      follow_redirect!
      expect(inertia.props[:errors]).to include("rain_in", "canopy")
      expect(field.field_entries).to be_empty
      expect(planting.canopy_observations).to be_empty
    end

    it "changes the balance on the next page load" do
      get field_path(field)
      before = inertia.props[:days].last[:ad]
      patch url, params: {day: {soil_moisture_pct: 5}, planting_id: planting.id}
      get field_path(field)
      expect(inertia.props[:days].last[:ad]).to be < before
    end
  end

  describe "the dashboard" do
    it "shows a card per field with its status today" do
      create(:field, pivot:, name: "Bare")
      get root_path
      cards = inertia.props[:cards].index_by { |card| card[:field][:name] }
      expect(cards["North potatoes"][:summary]).to include(phase: "active", status: "ok") # AD 1.05 of 1.2
      expect(cards["North potatoes"][:summary][:recent].size).to eq(20)
      expect(cards["Bare"][:summary]).to be_nil
      expect(inertia.props[:farm_count]).to eq(1)
    end

    it "offers the guided setup to a new account" do
      sign_in create(:user)
      get root_path
      expect(inertia.props).to include(cards: [], farm_count: 0)
    end
  end

  describe "pivot irrigation" do
    let!(:other_field) { create(:field, pivot:, name: "North corn", area_acres: 50) }

    it "creates, replaces by date, edits and deletes" do
      post pivot_irrigations_path(pivot), params: {pivot_irrigation: {date: "2026-07-10", inches: 0.8, field_ids: ["", field.id, other_field.id]}}
      irrigation = pivot.pivot_irrigations.sole
      expect(irrigation).to have_attributes(inches: 0.8, field_ids: nil) # every field: stored as all

      post pivot_irrigations_path(pivot), params: {pivot_irrigation: {date: "2026-07-10", inches: 0.7, field_ids: ["", field.id]}}
      expect(irrigation.reload).to have_attributes(inches: 0.7, field_ids: [field.id])

      patch pivot_irrigation_path(pivot, irrigation), params: {pivot_irrigation: {inches: "", run_hours: 12}}
      expect(irrigation.reload).to have_attributes(inches: nil, run_hours: 12)

      delete pivot_irrigation_path(pivot, irrigation)
      expect(pivot.pivot_irrigations).to be_empty
    end

    it "refuses an irrigation applied to no fields" do
      post pivot_irrigations_path(pivot), params: {pivot_irrigation: {date: "2026-07-10", inches: 0.8, field_ids: [""]}},
        headers: {"HTTP_REFERER" => pivot_path(pivot)}
      expect(pivot.pivot_irrigations).to be_empty
      follow_redirect!
      expect(inertia.props[:errors]).to include("field_ids")
    end

    it "lists a season's irrigation on the pivot page" do
      pivot.pivot_irrigations.create!(date: Date.new(2026, 7, 10), inches: 0.8)
      pivot.pivot_irrigations.create!(date: Date.new(2025, 7, 10), inches: 0.8)
      get pivot_path(pivot)
      expect(inertia.props[:irrigations].map { |i| i[:date] }).to eq(["2026-07-10"])
    end
  end

  describe "bulk daily entry" do
    let!(:other_field) { create(:field, pivot:, name: "North corn", area_acres: 50) }

    it "shows every pivot and field for a date with modeled rain" do
      get daily_entry_path(date: "2026-07-05")
      pivot_props = inertia.props[:farms].sole[:pivots].sole
      expect(pivot_props[:fields].map { |f| [f[:name], f[:rain_model]] }).to eq([["North corn", 0.4], ["North potatoes", 0.4]])
      expect(inertia.props[:date]).to eq("2026-07-05")
    end

    it "saves pivot irrigation and field entries for the day together" do
      patch daily_entry_path, params: {
        date: "2026-07-15",
        pivots: {pivot.id => {inches: "", run_hours: 10, field_ids: ["", other_field.id]}},
        fields: {field.id => {rain_in: 0.3, irrigation_in: "", soil_moisture_pct: ""}, other_field.id => {rain_in: "0"}}
      }
      expect(response).to redirect_to(daily_entry_path(date: "2026-07-15"))
      expect(pivot.pivot_irrigations.sole).to have_attributes(run_hours: 10, field_ids: [other_field.id])
      expect(field.field_entries.sole).to have_attributes(rain_in: 0.3, irrigation_in: nil)
      expect(other_field.field_entries.sole.rain_in).to eq(0.0)

      # Blank amounts remove the pivot's irrigation and empty entries
      patch daily_entry_path, params: {date: "2026-07-15", pivots: {pivot.id => {inches: "", run_hours: ""}},
                                       fields: {field.id => {rain_in: ""}}}
      expect(pivot.pivot_irrigations).to be_empty
      expect(field.field_entries).to be_empty
    end

    it "saves nothing when any value is invalid" do
      patch daily_entry_path, params: {date: "2026-07-15", pivots: {pivot.id => {inches: 0.5}},
                                       fields: {field.id => {soil_moisture_pct: 140}}}
      expect(pivot.pivot_irrigations).to be_empty
      follow_redirect!
      expect(inertia.props[:errors]).to include("fields.#{field.id}.soil_moisture_pct")
    end
  end

  describe "field groups" do
    it "creates a group, edits its members, records values that reach member fields, and deletes it" do
      post field_groups_path, params: {field_group: {name: "Home gauge", field_ids: ["", field.id]}}
      gauge = group.field_groups.sole
      expect(gauge.fields).to eq([field])

      patch field_group_day_path(gauge, "2026-07-08"), params: {day: {rain_in: 1.2}}
      expect(gauge.field_group_entries.sole.rain_in).to eq(1.2)

      get field_path(field)
      expect(inertia.props[:days].find { |day| day[:date] == "2026-07-08" }).to include(rain: 1.2, rain_source: "group")
      expect(inertia.props[:field_groups]).to eq([{"id" => gauge.id, "name" => "Home gauge"}])

      get field_group_path(gauge)
      expect(inertia.props[:days].find { |day| day[:date] == "2026-07-08" }).to include(rain_in: 1.2)

      patch field_group_path(gauge), params: {field_group: {name: "Gauge", field_ids: [""]}}
      expect(gauge.reload).to have_attributes(name: "Gauge", fields: [])

      delete field_group_path(gauge)
      expect(group.field_groups).to be_empty
    end
  end
end

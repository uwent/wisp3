require "rails_helper"

RSpec.describe "Daily entry", type: :request do
  let(:user) { create(:user) }
  let(:farm) { create(:farm, group: user.groups.first, name: "Home") }
  let(:pivot_group) { create(:pivot_group, farm:, name: "Home gauge") }
  let(:pivot) { create(:pivot, farm:, pivot_group:, name: "River") }
  let(:field) { create(:field, pivot:, name: "North", area_acres: 40) }
  let(:corn) { create(:plant, key: "corn", name: "Corn") }
  let!(:whole) do
    create(:planting, field:, plant: corn, season_start: Date.new(2026, 4, 20), emergence_date: Date.new(2026, 5, 10),
      end_date: Date.new(2026, 9, 30))
  end
  let(:date) { Date.new(2026, 7, 15) }

  before { sign_in user }

  around { |example| travel_to(Date.new(2026, 7, 20)) { example.run } }

  describe "the page", :inertia do
    it "lists farms with their pivot groups, pivots, fields and plantings in season" do
      get daily_entry_path(date:)
      farm_props = inertia.props[:farms].sole
      expect(farm_props[:pivot_groups]).to eq([{"id" => pivot_group.id, "name" => "Home gauge"}])
      pivot_props = farm_props[:pivots].sole
      expect(pivot_props).to include(name: "River", pivot_group_id: pivot_group.id)
      field_props = pivot_props[:fields].sole
      expect(field_props[:plantings].sole).to include(id: whole.id, plant_name: "Corn", partial: false, entry: nil)
    end

    it "lists a field's plots after its whole-field planting, with their own entries" do
      field.update!(area_acres: 40)
      whole.update!(end_date: Date.new(2026, 6, 30))
      plot = create(:planting, field:, plant: corn, partial: true, plot_length_ft: 100, plot_width_ft: 20,
        season_start: Date.new(2026, 7, 1), emergence_date: Date.new(2026, 7, 5), end_date: Date.new(2026, 9, 30))
      plot.planting_entries.create!(date:, irrigation_in: 0.3)
      get daily_entry_path(date:)
      plantings = inertia.props[:farms].sole[:pivots].sole[:fields].sole[:plantings]
      expect(plantings.sole).to include(id: plot.id, partial: true, plot_length_ft: 100.0,
        entry: {"irrigation_in" => 0.3, "soil_moisture_pct" => nil})
    end

    it "asks for a canopy reading from emergence until the canopy closes" do
      get daily_entry_path(date: Date.new(2026, 5, 1))
      expect(planting_props[:cover]).to be_nil

      get daily_entry_path(date:)
      expect(planting_props[:cover]).to eq("kind" => "pct_cover", "value" => nil, "due" => true, "last_date" => nil)

      create(:canopy_observation, planting: whole, date: Date.new(2026, 7, 10), pct_cover: 60)
      get daily_entry_path(date:)
      expect(planting_props[:cover]).to eq("kind" => "pct_cover", "value" => nil, "due" => false, "last_date" => "2026-07-10")

      create(:canopy_observation, planting: whole, date: Date.new(2026, 7, 12), pct_cover: 85)
      get daily_entry_path(date:)
      expect(planting_props[:cover]).to be_nil

      # A reading that day is always shown
      create(:canopy_observation, planting: whole, date:, pct_cover: 90)
      get daily_entry_path(date:)
      expect(planting_props[:cover]).to include("value" => 90.0)
    end

    def planting_props = inertia.props[:farms].sole[:pivots].sole[:fields].sole[:plantings].sole
  end

  describe "saving" do
    let(:plot_field) { create(:field, pivot:, name: "Plots", area_acres: 2) }
    let(:plot) do
      create(:planting, field: plot_field, plant: corn, partial: true, area_acres: 0.5,
        season_start: Date.new(2026, 5, 1), emergence_date: Date.new(2026, 5, 10), end_date: Date.new(2026, 9, 30))
    end

    it "saves rain, a plot's own irrigation and soil moisture, and canopy readings" do
      patch daily_entry_path, params: {date: date.iso8601,
                                       fields: {field.id => {rain_in: "0.4", irrigation_in: "", soil_moisture_pct: ""}},
                                       plantings: {plot.id => {irrigation_in: "0.25", soil_moisture_pct: "18"}},
                                       canopy: {whole.id => "55", plot.id => "30"}}
      expect(response).to redirect_to(daily_entry_path(date: date.iso8601))
      expect(field.field_entries.sole).to have_attributes(date:, rain_in: 0.4)
      expect(plot.planting_entries.sole).to have_attributes(irrigation_in: 0.25, soil_moisture_pct: 18.0)
      expect(whole.canopy_observations.sole).to have_attributes(date:, pct_cover: 55.0)
      expect(plot.canopy_observations.sole.pct_cover).to eq(30.0)
    end

    it "keeps a plot's notes when its irrigation is cleared, and removes a cleared reading" do
      plot.planting_entries.create!(date:, irrigation_in: 0.25, notes: "Drip")
      create(:canopy_observation, planting: whole, date:, pct_cover: 55)
      patch daily_entry_path, params: {date: date.iso8601,
                                       plantings: {plot.id => {irrigation_in: "", soil_moisture_pct: ""}}, canopy: {whole.id => ""}}
      expect(plot.planting_entries.sole).to have_attributes(irrigation_in: nil, notes: "Drip")
      expect(whole.canopy_observations).to be_empty
    end

    it "writes no plot entry for a whole-field planting" do
      patch daily_entry_path, params: {date: date.iso8601, plantings: {whole.id => {irrigation_in: "1"}}}
      expect(PlantingEntry.count).to eq(0)
    end

    it "saves nothing when a value is invalid", :inertia do
      patch daily_entry_path, params: {date: date.iso8601, fields: {field.id => {rain_in: "0.4"}},
                                       canopy: {whole.id => "140"}}
      expect(field.field_entries).to be_empty
      follow_redirect!
      expect(inertia.props[:errors]).to include("canopy.#{whole.id}" => ["Percent cover must be between 0 and 100"])
    end
  end
end

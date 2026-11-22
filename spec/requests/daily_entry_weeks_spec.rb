require "rails_helper"

RSpec.describe "Daily entry's week", type: :request do
  let(:user) { create(:user) }
  let(:farm) { create(:farm, group: user.groups.first, name: "Home") }
  let(:pivot_group) { create(:pivot_group, farm:, name: "East") }
  let(:pivot) { create(:pivot, farm:, pivot_group:, name: "River") }
  let(:north) { create(:field, pivot:, name: "North", area_acres: 40) }
  let(:south) { create(:field, pivot:, name: "South", area_acres: 30) }
  let(:date) { Date.new(2026, 7, 19) }
  let(:day) { Date.new(2026, 7, 15) }

  before do
    [north, south].each do |field|
      create(:planting, field:, season_start: Date.new(2026, 4, 20), emergence_date: Date.new(2026, 5, 10),
        end_date: Date.new(2026, 9, 30))
    end
    sign_in user
  end

  around { |example| travel_to(Time.zone.parse("2026-07-20 13:00")) { example.run } }

  def save(days, week_end = date) = patch(daily_entry_week_path, params: {date: week_end.iso8601, days:})

  describe "the page" do
    it "shows the seven days ending on the date chosen, else on daily entry's day" do
      get daily_entry_week_path(date:)
      expect(inertia).to render_component("DailyEntries/Week")
      expect(inertia.props[:dates]).to eq(("2026-07-13".."2026-07-19").to_a)
      expect(inertia.props[:farms].sole[:rain_rows].sole[:name]).to eq("East")

      get daily_entry_week_path
      expect(inertia.props[:date]).to eq("2026-07-20") # from noon, today
    end
  end

  describe "saving" do
    it "saves a plot's irrigation sent for a field growing only plots" do
      plots = create(:field, pivot:, name: "Plots")
      plot = create(:planting, field: plots, partial: true, area_acres: 1, season_start: Date.new(2026, 4, 20),
        emergence_date: Date.new(2026, 5, 10), end_date: Date.new(2026, 9, 30))
      save({day.iso8601 => {plantings: {plot.id => {irrigation_in: "0.6"}}}})
      expect(plot.planting_entries.sole).to have_attributes(date: day, irrigation_in: 0.6)
      expect(plots.field_entries).to be_empty
    end

    it "fills the fields sent with rain, keeping the rest of each field's entry" do
      north.field_entries.create!(date: day, irrigation_in: 0.5, soil_moisture_pct: 20, notes: "Gauge")
      save({day.iso8601 => {fields: {north.id => {rain_in: "0.4"}, south.id => {rain_in: "0.4"}}}})
      expect(response).to redirect_to(daily_entry_week_path(date: date.iso8601))
      expect(flash[:notice]).to eq("Saved Jul 13–19")
      expect(north.field_entries.sole).to have_attributes(rain_in: 0.4, irrigation_in: 0.5, soil_moisture_pct: 20.0, notes: "Gauge")
      expect(south.field_entries.sole).to have_attributes(date: day, rain_in: 0.4)
    end

    def irrigation(field) = field.field_entries.order(:date).where.not(irrigation_in: nil).map { |e| [e.date, e.irrigation_in] }

    it "creates, changes and removes each field's irrigation on several days, keeping the rest of its entry" do
      north.field_entries.create!(date: day, irrigation_in: 0.6)
      south.field_entries.create!(date: day + 1, irrigation_in: 0.8, notes: "Night")
      save({day.iso8601 => {fields: {north.id => {irrigation_in: "0.7"}}},
            (day + 1).iso8601 => {fields: {south.id => {irrigation_in: ""}}},
            (day + 2).iso8601 => {fields: {north.id => {irrigation_in: "1.0"}, south.id => {irrigation_in: "1.0"}}}})
      expect(irrigation(north)).to eq([[day, 0.7], [day + 2, 1.0]])
      expect(irrigation(south)).to eq([[day + 2, 1.0]])
      expect(south.field_entries.find_by(date: day + 1)).to have_attributes(irrigation_in: nil, notes: "Night")
    end

    it "sets a field's plots that had its irrigation" do
      plotted = create(:field, pivot:, name: "Plots", area_acres: 2)
      plot = create(:planting, field: plotted, partial: true, area_acres: 0.5, season_start: Date.new(2026, 4, 20),
        emergence_date: Date.new(2026, 5, 10), end_date: Date.new(2026, 9, 30))
      save({day.iso8601 => {fields: {plotted.id => {irrigation_in: "0.7"}}}})
      expect(plot.planting_entries.sole).to have_attributes(date: day, irrigation_in: 0.7)
    end

    it "takes planned irrigation ahead of today, but not rain, and saves nothing then" do
      ahead = Date.new(2026, 7, 22)
      save({(day + 3).iso8601 => {fields: {north.id => {rain_in: "0.3"}}},
            ahead.iso8601 => {fields: {north.id => {rain_in: "0.4"}, south.id => {irrigation_in: "1.0"}}}}, ahead + 1)
      expect(FieldEntry.count).to eq(0)
      follow_redirect!
      expect(inertia.props[:errors].keys).to eq(["days.2026-07-22.fields.#{north.id}.rain_in"])

      save({ahead.iso8601 => {fields: {north.id => {irrigation_in: "1.0"}}}}, ahead + 1)
      expect(north.field_entries.sole).to have_attributes(date: ahead, irrigation_in: 1.0)
    end

    it "keys each error by its day and record" do
      save({day.iso8601 => {fields: {north.id => {irrigation_in: "-1"}}}})
      follow_redirect!
      expect(inertia.props[:errors]).to eq("days.2026-07-15.fields.#{north.id}.irrigation_in" => ["Irrigation must be greater than or equal to 0"])
    end

    it "refuses a day outside the week" do
      save({(date + 1).iso8601 => {fields: {north.id => {rain_in: "0.3"}}}})
      expect(response).to have_http_status(:bad_request)
      expect(FieldEntry.count).to eq(0)
    end
  end
end

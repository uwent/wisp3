require "rails_helper"

# A center pivot's or linear's percent timer (docs/plans/phase-9.md §8): the depth at 100% on the
# system, irrigation entered as a percent with its circles, and a field's own amount as the percent
# its sector ran at
RSpec.describe "The percent timer", type: :request do
  let(:user) { create(:user) }
  let(:farm) { create(:farm, group: user.groups.first, name: "Home") }
  let(:pivot) { create(:pivot, farm:, name: "River", inches_at_100: 0.2) }
  let!(:west) { create(:field, pivot:, name: "West", area_acres: 60) }
  let!(:east) { create(:field, pivot:, name: "East", area_acres: 60) }
  let(:date) { Date.new(2026, 7, 15) }

  before { sign_in user }

  around { |example| travel_to(Date.new(2026, 7, 20)) { example.run } }

  describe "on the system" do
    it "is kept only for a pivot or linear, and at most 3 inches" do
      expect(pivot.percent_timer?).to be(true)
      pivot.update!(kind: "traveler")
      expect(pivot.reload).to have_attributes(inches_at_100: nil, percent_timer?: false)
      expect(build(:pivot, inches_at_100: 4).tap(&:validate).errors[:inches_at_100]).to be_present
      expect(build(:pivot, inches_at_100: 0).tap(&:validate).errors[:inches_at_100]).to be_present
    end

    it "is saved from the system's form" do
      patch pivot_path(pivot), params: {pivot: {inches_at_100: "0.25"}}
      expect(pivot.reload.inches_at_100).to eq(0.25)
    end
  end

  describe "an irrigation entered as a percent" do
    it "puts on the depth at 100% × 100 ÷ percent for each circle, converted when read" do
      irrigation = pivot.pivot_irrigations.create!(date:, percent_timer: 40)
      expect(irrigation).to have_attributes(entered_as: :percent, circles: nil)
      expect(irrigation.applied_inches).to be_within(1e-9).of(0.5)
      irrigation.update!(circles: 0.5)
      expect(irrigation.applied_inches).to be_within(1e-9).of(0.25)
      # One circle is stored as the default
      irrigation.update!(circles: 1)
      expect(irrigation.reload.circles).to be_nil
      # A corrected chart value corrects the season
      pivot.update!(inches_at_100: 0.3)
      expect(irrigation.reload.applied_inches).to be_within(1e-9).of(0.75)
    end

    it "needs the system's depth at 100%, and a percent from 0 to 100" do
      pivot.update!(inches_at_100: nil)
      irrigation = pivot.pivot_irrigations.build(date:, percent_timer: 40)
      expect(irrigation).not_to be_valid
      expect(irrigation.errors[:percent_timer].first).to include("depth at 100%")
      pivot.update!(inches_at_100: 0.2)
      expect(pivot.pivot_irrigations.build(date:, percent_timer: 120)).not_to be_valid
    end

    it "drops circles entered with inches" do
      irrigation = pivot.pivot_irrigations.create!(date:, inches: 0.6, circles: 2)
      expect(irrigation.circles).to be_nil
    end

    it "counts in the water balance" do
      planting = create(:planting, field: west, season_start: Date.new(2026, 5, 1), emergence_date: Date.new(2026, 5, 10),
        end_date: Date.new(2026, 9, 30))
      pivot.pivot_irrigations.create!(date:, percent_timer: 50)
      day = DailyInputs.new(west, [date], planting:).days.sole
      expect(day).to have_attributes(irrigation_source: :pivot)
      expect(day.irrigation).to be_within(1e-9).of(0.4)
    end
  end

  describe "daily entry" do
    it "saves the system's percent and circles, and a field's percent as the inches it comes to" do
      patch daily_entry_path, params: {date: date.iso8601,
                                       pivots: {pivot.id => {inches: "", run_hours: "", percent_timer: "100", circles: "2"}},
                                       fields: {east.id => {irrigation_in: "", irrigation_pct: "50"}}}
      expect(response).to redirect_to(daily_entry_path(date: date.iso8601))
      expect(pivot.pivot_irrigations.sole).to have_attributes(percent_timer: 100.0, circles: 2.0, inches: nil)
      expect(east.field_entries.sole).to have_attributes(irrigation_in: 0.4, irrigation_pct: 50.0)
    end

    it "refuses a field's percent when its system has no depth at 100%", :inertia do
      pivot.update!(inches_at_100: nil)
      patch daily_entry_path, params: {date: date.iso8601, fields: {east.id => {rain_in: "0.2", irrigation_pct: "50"}}}
      expect(east.field_entries).to be_empty
      follow_redirect!
      expect(inertia.props[:errors]["fields.#{east.id}.irrigation_pct"].first).to include("depth at 100%")
    end

    it "keeps a field's percent unless its inches change some other way" do
      east.field_entries.create!(date:, irrigation_in: 0.4, irrigation_pct: 50)
      FieldEntry.record(east.field_entries, date, irrigation_in: 0.4, rain_in: 0.1)
      expect(east.field_entries.sole).to have_attributes(irrigation_pct: 50.0, rain_in: 0.1)
      FieldEntry.record(east.field_entries, date, irrigation_in: 0.5)
      expect(east.field_entries.sole).to have_attributes(irrigation_in: 0.5, irrigation_pct: nil)
    end

    it "offers the percent to systems that have it", :inertia do
      get daily_entry_path(date: date.iso8601)
      river = inertia.props[:farms].first[:pivots].sole
      expect(river[:inches_at_100]).to eq(0.2)
    end
  end

  describe "the system page's irrigation form" do
    it "saves each field's own amount, as inches or a percent, and clears one left blank" do
      west.field_entries.create!(date:, irrigation_in: 0.9, rain_in: 0.3)
      post pivot_irrigations_path(pivot), params: {pivot_irrigation: {
        date: date.iso8601, inches: "", run_hours: "", percent_timer: "100", circles: "",
        field_ids: ["", west.id, east.id],
        field_amounts: {west.id => {irrigation_in: ""}, east.id => {irrigation_in: "", irrigation_pct: "50"}}
      }}
      expect(pivot.pivot_irrigations.sole).to have_attributes(percent_timer: 100.0, field_ids: nil)
      expect(west.field_entries.sole).to have_attributes(irrigation_in: nil, rain_in: 0.3)
      expect(east.field_entries.sole).to have_attributes(irrigation_in: 0.4, irrigation_pct: 50.0)
    end

    it "lists the fields' own amounts", :inertia do
      pivot.pivot_irrigations.create!(date:, percent_timer: 100)
      east.field_entries.create!(date:, irrigation_in: 0.4, irrigation_pct: 50)
      get pivot_path(pivot, year: 2026)
      expect(inertia.props[:field_amounts]).to eq(date.iso8601 => {east.id.to_s => {"irrigation_in" => 0.4, "irrigation_pct" => 50.0}})
      expect(inertia.props[:pivot]["inches_at_100"]).to eq(0.2)
    end

    it "saves nothing when a field's amount is refused", :inertia do
      post pivot_irrigations_path(pivot), params: {pivot_irrigation: {
        date: date.iso8601, inches: "0.6", field_amounts: {east.id => {irrigation_in: "", irrigation_pct: "250"}}
      }}
      expect(pivot.pivot_irrigations).to be_empty
      follow_redirect!
      expect(inertia.props[:errors]).to have_key("fields.#{east.id}.irrigation_pct")
    end

    it "takes the fields' own amounts with it when deleted or moved to another day" do
      irrigation = pivot.pivot_irrigations.create!(date:, percent_timer: 100)
      east.field_entries.create!(date:, irrigation_in: 0.4, irrigation_pct: 50, rain_in: 0.2)
      patch pivot_irrigation_path(pivot, irrigation), params: {pivot_irrigation: {date: (date + 1).iso8601}}
      expect(east.field_entries.find_by(date:)).to have_attributes(irrigation_in: nil, irrigation_pct: nil, rain_in: 0.2)

      east.field_entries.create!(date: date + 1, irrigation_in: 0.4)
      delete pivot_irrigation_path(pivot, irrigation)
      expect(PivotIrrigation.where(pivot:)).to be_empty
      expect(east.field_entries.find_by(date: date + 1)).to be_nil
    end
  end
end

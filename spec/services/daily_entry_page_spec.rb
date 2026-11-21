require "rails_helper"

RSpec.describe DailyEntryPage do
  let(:group) { create(:group) }
  let(:farm) { create(:farm, group:) }
  let(:ran) { create(:pivot, farm:, name: "Ran") }
  let(:by_hours) { create(:pivot, farm:, name: "Hours", pump_capacity_gpm: 800) }
  let(:entered) { create(:pivot, farm:, name: "Entered") }
  let(:date) { Date.new(2026, 7, 20) }

  around { |example| travel_to(date) { example.run } }

  def pivot_props(page, pivot)
    page.props[:farms].sole[:pivots].find { |props| props[:id] == pivot.id }
  end

  describe "yesterday's irrigation" do
    it "offers the day before's amount, as entered, for systems with nothing entered this day" do
      field = create(:field, pivot: ran)
      create(:pivot_irrigation, pivot: ran, date: date - 1, inches: 0.8, field_ids: [field.id])
      create(:field, pivot: by_hours, area_acres: 60)
      create(:pivot_irrigation, pivot: by_hours, date: date - 1, inches: nil, run_hours: 10)
      create(:pivot_irrigation, pivot: entered, date: date - 1, inches: 0.5)
      create(:pivot_irrigation, pivot: entered, date:, inches: 0.6)
      create(:pivot_irrigation, pivot: create(:pivot, farm:, name: "Earlier"), date: date - 2, inches: 1.0)

      page = described_class.new(group, date)
      expect(pivot_props(page, ran)[:yesterday]).to eq("inches" => 0.8, "run_hours" => nil, "field_ids" => [field.id])
      expect(pivot_props(page, by_hours)[:yesterday]).to include("inches" => nil, "run_hours" => 10)
      expect(pivot_props(page, entered)[:yesterday]).to be_nil
      expect(page.props[:farms].sole[:pivots].find { |props| props[:name] == "Earlier" }[:yesterday]).to be_nil
    end

    it "reads every system's in one query" do
      [ran, by_hours].each { |pivot| create(:pivot_irrigation, pivot:, date: date - 1) }
      page = described_class.new(group, date)
      page.farms
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?("pivot_irrigations") }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { page.props }
      expect(queries.size).to eq(2) # this day's and the day before's
    end
  end
end

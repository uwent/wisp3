require "rails_helper"

RSpec.describe DailyEntryPage do
  let(:group) { create(:group) }
  let(:farm) { create(:farm, group:) }
  let(:ran) { create(:pivot, farm:, name: "Ran", inches_at_100: 0.25) }
  let(:entered) { create(:pivot, farm:, name: "Entered") }
  let(:date) { Date.new(2026, 7, 20) }

  around { |example| travel_to(date) { example.run } }

  def pivot_props(page, pivot)
    page.props[:farms].sole[:pivots].find { |props| props[:id] == pivot.id }
  end

  describe "yesterday's irrigation" do
    it "offers the day before's amounts on the fields and plots, for systems with none this day" do
      field = create(:field, pivot: ran, name: "A")
      dry = create(:field, pivot: ran, name: "B")
      plotted = create(:field, pivot: ran, name: "C")
      plot = create(:planting, field: plotted, partial: true, area_acres: 1, season_start: date - 60,
        emergence_date: date - 50, end_date: date + 60)
      field.field_entries.create!(date: date - 1, irrigation_in: 0.8)
      dry.field_entries.create!(date: date - 1, rain_in: 0.3)
      plot.planting_entries.create!(date: date - 1, irrigation_in: 0.4)
      dry.field_entries.create!(date:, rain_in: 0.2) # rain this day still offers it
      on_entered = create(:field, pivot: entered)
      on_entered.field_entries.create!(date: date - 1, irrigation_in: 0.5)
      on_entered.field_entries.create!(date:, irrigation_in: 0.6)
      create(:field, pivot: create(:pivot, farm:, name: "Earlier")).field_entries.create!(date: date - 2, irrigation_in: 1.0)

      page = described_class.new(group, date)
      expect(pivot_props(page, ran)).to include(inches_at_100: 0.25,
        yesterday: {fields: {field.id => 0.8}, plantings: {plot.id => 0.4}})
      expect(pivot_props(page, ran)).not_to have_key(:irrigation)
      expect(pivot_props(page, entered)[:yesterday]).to be_nil
      expect(page.props[:farms].sole[:pivots].find { |props| props[:name] == "Earlier" }[:yesterday]).to be_nil
      expect(pivot_props(page, ran)[:fields].find { |props| props[:id] == dry.id }[:entry])
        .to eq("rain_in" => 0.2, "irrigation_in" => nil, "soil_moisture_pct" => nil)
    end

    it "offers nothing once a plot has irrigation this day" do
      field = create(:field, pivot: ran)
      plot = create(:planting, field:, partial: true, area_acres: 1, season_start: date - 60,
        emergence_date: date - 50, end_date: date + 60)
      field.field_entries.create!(date: date - 1, irrigation_in: 0.8)
      plot.planting_entries.create!(date:, irrigation_in: 0.0)
      expect(pivot_props(described_class.new(group, date), ran)[:yesterday]).to be_nil
    end

    it "reads every system's in a fixed number of queries" do
      [ran, entered].each do |pivot|
        2.times do
          field = create(:field, pivot:)
          field.field_entries.create!(date: date - 1, irrigation_in: 0.5)
          create(:planting, field:, partial: true, area_acres: 1, season_start: date - 60, emergence_date: date - 50,
            end_date: date + 60)
        end
      end
      page = described_class.new(group, date)
      page.farms
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].match?(/field_entries|planting_entries/) }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { page.props }
      expect(queries.size).to eq(4) # this day's and the day before's, of fields and of plots
    end
  end
end

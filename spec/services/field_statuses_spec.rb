require "rails_helper"

RSpec.describe FieldStatuses do
  # The example farm (Current.as_of, PLAN.md G.8): each planting as time travel sees it, from the records
  # FieldStatuses loaded for every field rather than its own
  describe "as of a day" do
    let(:as_of) { Date.new(2026, 7, 20) }
    let(:pivot) { create(:pivot) }

    def add_field
      field = create(:field, pivot:)
      create(:planting, field:, season_start: Date.new(2026, 5, 1), emergence_date: Date.new(2026, 5, 10),
        end_date: Date.new(2026, 9, 15))
      field.field_entries.create!(date: as_of - 3, irrigation_in: 0.5)
      # What happened next: entered after the day, it's the projection's
      field.field_entries.create!(date: as_of + 2, irrigation_in: 0.8)
      field
    end

    def statuses_for(fields)
      scope = Field.where(id: fields.map(&:id)).includes(:soil_type, pivot: :weather_cell,
        plantings: [:plant, :canopy_observations, :canopy_cuttings, :soil_type, :weather_cell, :pivot])
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
      statuses = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        described_class.for(scope.to_a, today: as_of, as_of:).values.flatten.each(&:forecast_days)
      end
      [count, statuses]
    end

    before do
      (Date.new(2026, 5, 1)..as_of + PlantingStatus::HORIZON).each do |date|
        pivot.weather_cell.weather_days.create!(date:, et0_in: 0.2, precip_in: 0.0, model: "m", hours: 24, fetched_at: Time.current)
      end
    end

    it "gives each planting time travel's view, with the days that followed as its projection" do
      field = add_field
      _, statuses = statuses_for([field])
      status = statuses.sole
      alone = PlantingStatus.new(field.plantings.sole, as_of:)
      expect(status.projection_source).to eq(:observed)
      expect(status.days.map(&:result)).to eq(alone.days.map(&:result))
      expect(status.forecast_days.map(&:result)).to eq(alone.forecast_days.map(&:result))
      expect(status.forecast_days.size).to eq(PlantingStatus::HORIZON)
      expect(status.forecast_days.find { |day| day.inputs.date == as_of + 2 }.inputs.irrigation).to eq(0.8)
    end

    it "runs the same queries for one planting or several" do
      one, = statuses_for([add_field])
      several, statuses = statuses_for(Array.new(3) { add_field })
      expect(several).to eq(one)
      expect(statuses.size).to eq(3)
    end
  end
end

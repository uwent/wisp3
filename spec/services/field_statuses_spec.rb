require "rails_helper"

RSpec.describe FieldStatuses do
  describe "a field's plantings out of season" do
    let(:field) { create(:field) }
    let(:winter) { Date.new(2026, 11, 24) }

    def planting(start, finish, **attributes)
      create(:planting, field:, season_start: start, emergence_date: start + 10, end_date: finish, **attributes)
    end

    def shown(today) = described_class.for([field.reload], today:)[field.id].map { |status| [status.planting, status.phase] }

    it "shows next season's planting, set up over the winter, on a field with nothing this year" do
      expect(shown(winter)).to eq([])
      next_season = planting(Date.new(2027, 5, 1), Date.new(2027, 9, 15))
      planting(Date.new(2028, 5, 1), Date.new(2028, 9, 15))
      expect(shown(winter)).to eq([[next_season, :upcoming]])
    end

    it "keeps this year's ended season until the year turns" do
      ended = planting(Date.new(2026, 5, 1), Date.new(2026, 9, 15))
      next_season = planting(Date.new(2027, 5, 1), Date.new(2027, 9, 15))
      expect(shown(winter)).to eq([[ended, :ended]])
      expect(shown(Date.new(2027, 1, 15))).to eq([[next_season, :upcoming]])
    end

    it "shows a season that runs over the new year as in season on both sides of it" do
      winter_crop = planting(Date.new(2026, 9, 15), Date.new(2027, 7, 1))
      expect(shown(Date.new(2026, 12, 31))).to eq([[winter_crop, :active]])
      expect(shown(Date.new(2027, 1, 15))).to eq([[winter_crop, :active]])
    end
  end

  # The example farm (Current.as_of): each planting as time travel sees it, from the records
  # FieldStatuses loaded for every field rather than its own
  describe "as of a day" do
    let(:as_of) { Date.new(2026, 7, 20) }
    let(:system) { create(:system) }

    def add_field
      field = create(:field, system:)
      create(:planting, field:, season_start: Date.new(2026, 5, 1), emergence_date: Date.new(2026, 5, 10),
        end_date: Date.new(2026, 9, 15))
      field.field_entries.create!(date: as_of - 3, irrigation_in: 0.5)
      # What happened next: entered after the day, it's the projection's
      field.field_entries.create!(date: as_of + 2, irrigation_in: 0.8)
      field
    end

    def statuses_for(fields)
      scope = Field.where(id: fields.map(&:id)).includes(:soil_type, system: :weather_cell,
        plantings: [:plant, :canopy_observations, :canopy_cuttings, :soil_type, :weather_cell, :system])
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
      statuses = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        described_class.for(scope.to_a, today: as_of, as_of:).values.flatten.each(&:forecast_days)
      end
      [count, statuses]
    end

    before do
      (Date.new(2026, 5, 1)..as_of + PlantingStatus::HORIZON).each do |date|
        system.weather_cell.weather_days.create!(date:, et0_in: 0.2, precip_in: 0.0, model: "m", hours: 24, fetched_at: Time.current)
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

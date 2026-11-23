require "rails_helper"

RSpec.describe DailyInputs do
  let(:date) { Date.new(2026, 6, 1) }
  let(:system) { create(:system, pump_capacity_gpm: 900) }
  let(:field) { create(:field, system:, area_acres: 60) }
  let(:other_field) { create(:field, system:, area_acres: 40) }
  let(:weather) { {date => {et0: 0.22, precip: 0.35}} }

  def resolve(on = date, weather: self.weather) = described_class.new(field, [on], weather:).days.first

  it "uses the model with nothing entered" do
    expect(resolve).to have_attributes(rain: 0.35, rain_source: :model, rain_model: 0.35, irrigation: 0.0,
      irrigation_source: :none, et0: 0.22, et0_source: :model, soil_moisture_pct: nil, moisture_source: nil)
  end

  it "has nothing to resolve without dates" do
    expect(described_class.new(field, []).days).to eq([])
  end

  it "marks missing weather instead of using 0" do
    expect(resolve(weather: {})).to have_attributes(rain: nil, rain_source: :missing, et0: nil, et0_source: :missing)
  end

  it "uses 0 rain, not the model, when the farm enters rain by hand" do
    field.system.farm.update!(use_model_precip: false)
    expect(resolve).to have_attributes(rain: 0.0, rain_source: :none, rain_model: 0.35)
  end

  describe "the irrigation group's rainfall setting (Q7)" do
    let(:irrigation_group) { create(:irrigation_group, farm: system.farm, systems: [system]) }

    def resolve_for(field, on = date, today: date) = described_class.new(field.reload, [on], weather:, today:).days.first

    it "overrides the farm's either way, and follows it when not set" do
      irrigation_group.update!(use_model_precip: false)
      expect(resolve_for(field)).to have_attributes(rain: 0.0, rain_source: :none, rain_model: 0.35)
      system.farm.update!(use_model_precip: false)
      irrigation_group.update!(use_model_precip: true)
      expect(resolve_for(field)).to have_attributes(rain: 0.35, rain_source: :model)
      irrigation_group.update!(use_model_precip: nil)
      expect(resolve_for(field).rain_source).to eq(:none)
    end

    it "is the planting's system's for a season that ran on another" do
      irrigation_group.update!(use_model_precip: false)
      planting = create(:planting, field:, season_start: date - 30, end_date: date + 30)
      field.update!(system: create(:system, farm: system.farm))
      planting.update_columns(system_id: system.id)
      days = described_class.new(field.reload, [date], weather:, today: date, planting: planting.reload).days
      expect(days.first.rain_source).to eq(:none)
      expect(resolve_for(field).rain_source).to eq(:model)
    end

    it "still takes the forecast's rain after today, but not today's" do
      irrigation_group.update!(use_model_precip: false)
      ahead = {date => {et0: 0.2, precip: 0.4, forecast: true}}
      expect(described_class.new(field.reload, [date], weather: ahead, today: date - 1).days.first)
        .to have_attributes(rain: 0.4, rain_source: :forecast)
      expect(described_class.new(field, [date], weather: ahead, today: date).days.first)
        .to have_attributes(rain: 0.0, rain_source: :none)
    end
  end

  describe "precedence" do
    it "prefers the field's entry, keeping the modeled rain alongside" do
      create(:field_entry, field:, date:, rain_in: 0.8, irrigation_in: 0.5, soil_moisture_pct: 14)
      expect(resolve).to have_attributes(rain: 0.8, rain_source: :entered, rain_model: 0.35, irrigation: 0.5,
        irrigation_source: :entered, soil_moisture_pct: 14, moisture_source: :entered)
    end

    it "keeps an entered zero (C5)" do
      create(:field_entry, field:, date:, rain_in: 0.0, irrigation_in: 0.0)
      expect(resolve).to have_attributes(rain: 0.0, rain_source: :entered, irrigation: 0.0, irrigation_source: :entered)
    end

    it "takes no irrigation from the system or another field on it (D15)" do
      create(:field_entry, field: other_field, date:, irrigation_in: 0.7)
      create(:field_entry, field:, date:, rain_in: 0.6)
      expect(resolve).to have_attributes(rain: 0.6, rain_source: :entered, irrigation: 0.0, irrigation_source: :none,
        soil_moisture_pct: nil, moisture_source: nil)
      expect(described_class.new(other_field, [date]).days.first)
        .to have_attributes(irrigation: 0.7, irrigation_source: :entered)
    end
  end

  describe "a planting on part of the field" do
    let(:field) { create(:field, system:, area_acres: 60) }
    let!(:plot) { create(:planting, field:, partial: true, area_acres: 20, season_start: date - 30, end_date: date + 60) }

    def resolve_plot = described_class.new(field, [date], weather:, planting: plot.reload).days.first

    it "takes its own irrigation, not the field's" do
      create(:field_entry, field:, date:, irrigation_in: 0.5)
      expect(resolve_plot).to have_attributes(irrigation: 0.0, irrigation_source: :none)
      plot.planting_entries.create!(date:, irrigation_in: 0.3)
      expect(resolve_plot).to have_attributes(irrigation: 0.3, irrigation_source: :entered)
      expect(resolve).to have_attributes(irrigation: 0.5, irrigation_source: :entered)
    end
  end

  describe ".preload" do
    it "resolves every field's days exactly as querying them one field at a time does" do
      dates = (date..date + 4).to_a
      weather = dates.to_h { |day| [day, {et0: 0.2, precip: 0.1}] }
      create(:field_entry, field:, date: date + 1, rain_in: 0.8, soil_moisture_pct: 12)
      create(:field_entry, field:, date: date + 2, rain_in: 0.4, irrigation_in: 0.3)
      create(:field_entry, field: other_field, date: date + 3, irrigation_in: 0.7)
      create(:field_entry, field: other_field, date: date + 4, irrigation_in: 0.2)

      records = described_class.preload([field, other_field], dates.first..dates.last)
      [field, other_field].each do |each_field|
        expect(described_class.new(each_field, dates, weather:, records: records[each_field.id]).days)
          .to eq(described_class.new(each_field, dates, weather:).days)
      end
      expect(records[other_field.id].entries.size).to eq(2)
    end

    it "takes the same queries however many days it resolves" do
      plot = create(:planting, field:, partial: true, area_acres: 20, season_start: date - 30, emergence_date: date - 20, end_date: date + 60)
      weather = (date..date + 9).to_h { |day| [day, {et0: 0.2, precip: 0.0}] }
      queries = lambda do |days, planting|
        dates = (date..date + days - 1).to_a
        count = 0
        counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
        result = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          records = described_class.preload([field.reload], dates.first..dates.last)
          described_class.new(field, dates, weather:, records: records[field.id], planting:).days
        end
        [count, result]
      end

      (date..date + 9).each do |day|
        create(:field_entry, field:, date: day, irrigation_in: 0.5)
        plot.planting_entries.create!(date: day, irrigation_in: 0.4)
      end
      plot.reload
      queries.call(1, plot) # loads the planting's system once
      few, = queries.call(2, plot)
      many, days = queries.call(10, plot)
      expect(many).to eq(few)
      expect(days.map(&:irrigation)).to all(eq(0.4))
      expect(queries.call(10, nil).last.map(&:irrigation)).to all(eq(0.5))
    end
  end
end

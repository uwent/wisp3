require "rails_helper"

RSpec.describe DailyInputs do
  let(:date) { Date.new(2026, 6, 1) }
  let(:pivot) { create(:pivot, pump_capacity_gpm: 900) }
  let(:field) { create(:field, pivot:, area_acres: 60) }
  let(:other_field) { create(:field, pivot:, area_acres: 40) }
  let(:weather) { {date => {et0: 0.22, precip: 0.35}} }

  def resolve(on = date, weather: self.weather) = described_class.new(field, [on], weather:).days.first

  it "uses the model with nothing entered" do
    expect(resolve).to have_attributes(rain: 0.35, rain_source: :model, rain_model: 0.35, irrigation: 0.0,
      irrigation_source: :none, et0: 0.22, et0_source: :model, soil_moisture_pct: nil, moisture_source: nil)
  end

  it "marks missing weather instead of using 0" do
    expect(resolve(weather: {})).to have_attributes(rain: nil, rain_source: :missing, et0: nil, et0_source: :missing)
  end

  it "uses 0 rain, not the model, when the group enters rain by hand" do
    field.pivot.farm.group.update!(use_model_precip: false)
    expect(resolve).to have_attributes(rain: 0.0, rain_source: :none, rain_model: 0.35)
  end

  describe "the field's rainfall setting (Q7)" do
    def resolve_for(field, on = date, today: date) = described_class.new(field.reload, [on], weather:, today:).days.first

    it "overrides the group's either way, and follows it when not set" do
      field.update!(use_model_precip: false)
      expect(resolve_for(field)).to have_attributes(rain: 0.0, rain_source: :none, rain_model: 0.35)
      field.pivot.farm.group.update!(use_model_precip: false)
      field.update!(use_model_precip: true)
      expect(resolve_for(field)).to have_attributes(rain: 0.35, rain_source: :model)
      field.update!(use_model_precip: nil)
      expect(resolve_for(field).rain_source).to eq(:none)
    end

    it "still takes the forecast's rain after today, but not today's" do
      field.update!(use_model_precip: false)
      ahead = {date => {et0: 0.2, precip: 0.4, forecast: true}}
      expect(described_class.new(field, [date], weather: ahead, today: date - 1).days.first)
        .to have_attributes(rain: 0.4, rain_source: :forecast)
      expect(described_class.new(field, [date], weather: ahead, today: date).days.first)
        .to have_attributes(rain: 0.0, rain_source: :none)
    end
  end

  describe "precedence" do
    let(:field_group) { create(:field_group, group: field.farm.group).tap { |g| g.fields << field } }

    it "prefers the field's entry, keeping the modeled rain alongside" do
      create(:field_entry, field:, date:, rain_in: 0.8, irrigation_in: 0.5, soil_moisture_pct: 14)
      create(:field_group_entry, field_group:, date:, rain_in: 0.6, irrigation_in: 0.4, soil_moisture_pct: 12)
      create(:pivot_irrigation, pivot:, date:, inches: 0.7)
      expect(resolve).to have_attributes(rain: 0.8, rain_source: :entered, rain_model: 0.35, irrigation: 0.5,
        irrigation_source: :entered, soil_moisture_pct: 14, moisture_source: :entered)
    end

    it "keeps an entered zero (C5)" do
      create(:field_entry, field:, date:, rain_in: 0.0)
      expect(resolve).to have_attributes(rain: 0.0, rain_source: :entered)
    end

    it "puts pivot irrigation above field group irrigation" do
      create(:field_group_entry, field_group:, date:, rain_in: 0.6, irrigation_in: 0.4, soil_moisture_pct: 12)
      create(:pivot_irrigation, pivot:, date:, inches: 0.7)
      expect(resolve).to have_attributes(rain: 0.6, rain_source: :group, irrigation: 0.7, irrigation_source: :pivot,
        soil_moisture_pct: 12, moisture_source: :group)
    end

    it "takes a field in two field groups from the older group" do
      create(:field_group_entry, field_group:, date:, rain_in: 0.6)
      newer = create(:field_group, group: field.farm.group).tap { |g| g.fields << field }
      create(:field_group_entry, field_group: newer, date:, rain_in: 0.9)
      expect(resolve.rain).to eq(0.6)
    end
  end

  describe "pivot irrigation" do
    it "applies only to the chosen fields" do
      create(:pivot_irrigation, pivot:, date:, inches: 0.7, field_ids: [other_field.id])
      expect(resolve.irrigation_source).to eq(:none)
      expect(described_class.new(other_field, [date]).days.first.irrigation).to eq(0.7)
    end

    it "converts run hours over the irrigated acres" do
      field
      other_field
      create(:pivot_irrigation, pivot:, date:, inches: nil, run_hours: 10)
      # 900 gpm × 600 min / (27,154 gal per acre-inch × 100 acres)
      expect(resolve.irrigation).to be_within(1e-9).of(900 * 600 / (27_154.0 * 100))
    end
  end

  describe ".preload" do
    it "resolves every field's days exactly as querying them one field at a time does" do
      dates = (date..date + 4).to_a
      weather = dates.to_h { |day| [day, {et0: 0.2, precip: 0.1}] }
      gauge = create(:field_group, group: field.farm.group).tap { |g| g.fields << field }
      create(:field_entry, field:, date: date + 1, rain_in: 0.8, soil_moisture_pct: 12)
      create(:field_group_entry, field_group: gauge, date: date + 2, rain_in: 0.4, irrigation_in: 0.3)
      create(:pivot_irrigation, pivot:, date: date + 3, inches: 0.7, field_ids: [other_field.id])
      create(:field_entry, field: other_field, date: date + 4, irrigation_in: 0.2)

      records = described_class.preload([field, other_field], dates.first..dates.last)
      [field, other_field].each do |each_field|
        expect(described_class.new(each_field, dates, weather:, records: records[each_field.id]).days)
          .to eq(described_class.new(each_field, dates, weather:).days)
      end
      expect(records[other_field.id].pivot_irrigations.size).to eq(1)
    end
  end
end

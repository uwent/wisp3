require "rails_helper"

# PLAN.md Phase 8 G.11: a field is the land, a planting what grows on it, on the whole field or on
# part of it, with part-field plantings' own irrigation and readings first in their balance.
RSpec.describe "Part-field plantings" do
  let(:pivot) { create(:pivot, pump_capacity_gpm: 900) }
  let(:field) { create(:field, pivot:, area_acres: 10) }
  let(:season) { {season_start: Date.new(2026, 4, 1), emergence_date: Date.new(2026, 5, 15), end_date: Date.new(2026, 9, 30)} }

  def plot(length: 100, width: 20, **attributes)
    create(:planting, field:, partial: true, plot_length_ft: length, plot_width_ft: width, **season, **attributes)
  end

  around { |example| travel_to(Date.new(2026, 7, 1)) { example.run } }

  describe "areas and overlaps" do
    it "sizes a plot from its length and width" do
      expect(plot.area_acres).to be_within(1e-6).of(2000 / 43_560.0)
    end

    it "takes acres for part of a field without a length and width, and needs one or the other" do
      expect(create(:planting, field:, partial: true, area_acres: 0.5, **season).area_acres).to eq(0.5)
      expect(build(:planting, field:, partial: true, **season)).not_to be_valid
    end

    it "lets part-field plantings overlap each other, but not a whole-field one" do
      plot
      expect(plot(length: 50)).to be_persisted
      whole = build(:planting, field:, **season)
      expect(whole).not_to be_valid
      expect(whole.errors[:season_start]).to include("overlaps another planting on this field")
    end

    it "keeps a part-field planting off a field with a whole-field one" do
      create(:planting, field:, **season)
      part = build(:planting, field:, partial: true, area_acres: 1, **season)
      expect(part).not_to be_valid
      expect(part.errors[:season_start]).to include("overlaps a planting covering the whole field")
    end

    it "is enforced by the database too" do
      plot
      expect(build(:planting, field:, partial: true, area_acres: 1, **season).tap { |p| p.save!(validate: false) }).to be_persisted
      expect { build(:planting, field:, **season).save!(validate: false) }
        .to raise_error(ActiveRecord::StatementInvalid, /plantings_no_overlap/)
    end

    it "warns when plots in season together add up to more than the field" do
      first = plot(area_acres: nil, length: 660, width: 330) # 5 acres
      expect(first.exceeds_field_area?).to be(false)
      second = plot(length: 660, width: 400) # 6.06 acres
      expect(second.exceeds_field_area?).to be(true)
    end

    it "goes back to the whole field: no plot or pin, the field's area, unless it has its own entries" do
      part = plot(latitude: 44.1, longitude: -89.5)
      part.update!(partial: false)
      expect(part).to have_attributes(plot_length_ft: nil, latitude: nil, area_acres: 10)
      other = create(:field, pivot:, area_acres: 10)
      entered = create(:planting, field: other, partial: true, area_acres: 1, **season)
      entered.planting_entries.create!(date: Date.new(2026, 6, 1), irrigation_in: 0.3)
      expect(entered.update(partial: false)).to be(false)
    end

    it "keeps a plot's area when the field's area changes" do
      part = plot
      whole_field = create(:field, pivot:, area_acres: 10)
      whole = create(:planting, field: whole_field, **season)
      field.update!(area_acres: 12)
      whole_field.update!(area_acres: 12)
      expect(part.reload.area_acres).to be_within(1e-6).of(2000 / 43_560.0)
      expect(whole.reload.area_acres).to eq(12)
    end

    it "copies plots to the next season with their size" do
      plot
      SeasonCopy.new(field.pivot.farm.group, 2027).run
      copied = field.plantings.reload.find { |planting| planting.season_year == 2027 }
      expect(copied).to have_attributes(partial: true, plot_length_ft: 100, plot_width_ft: 20)
      expect(copied.area_acres).to be_within(1e-6).of(2000 / 43_560.0)
    end
  end

  describe "own entries" do
    let(:part) { plot }
    let(:dates) { (Date.new(2026, 6, 1)..Date.new(2026, 6, 4)).to_a }

    def days(planting, preload: false)
      records = DailyInputs.preload([field], dates.first..dates.last)[field.id] if preload
      DailyInputs.new(field, dates, records:, planting:).days.index_by(&:date)
    end

    before do
      field.field_entries.create!(date: dates[0], irrigation_in: 0.5, soil_moisture_pct: 12)
      field.field_entries.create!(date: dates[1], irrigation_in: 0.5, rain_in: 0.2)
      part.planting_entries.create!(date: dates[1], irrigation_in: 0.25, soil_moisture_pct: 9)
      pivot.pivot_irrigations.create!(date: dates[2], inches: 0.7)
    end

    it "come before the field's irrigation, take the field's as :field, and the pivot's after" do
      [false, true].each do |preload|
        inputs = days(part, preload:)
        expect(inputs[dates[0]]).to have_attributes(irrigation: 0.5, irrigation_source: :field)
        expect(inputs[dates[1]]).to have_attributes(irrigation: 0.25, irrigation_source: :entered, rain: 0.2)
        expect(inputs[dates[2]]).to have_attributes(irrigation: 0.7, irrigation_source: :pivot)
      end
    end

    it "use only the planting's own soil moisture readings" do
      inputs = days(part)
      expect(inputs[dates[0]].soil_moisture_pct).to be_nil
      expect(inputs[dates[1]]).to have_attributes(soil_moisture_pct: 9, moisture_source: :entered)
    end

    it "leave the field's other plantings and a whole-field planting as before" do
      other = plot(length: 50)
      expect(days(other)[dates[1]]).to have_attributes(irrigation: 0.5, irrigation_source: :field)
      whole_field = create(:field, pivot:)
      whole = create(:planting, field: whole_field, **season)
      whole_field.field_entries.create!(date: dates[0], irrigation_in: 0.5, soil_moisture_pct: 12)
      inputs = DailyInputs.new(whole_field, dates, planting: whole).days.index_by(&:date)
      expect(inputs[dates[0]]).to have_attributes(irrigation_source: :entered, soil_moisture_pct: 12)
    end

    it "belong only to part-field plantings" do
      whole = create(:planting, field: create(:field, pivot:), **season)
      expect(whole.planting_entries.build(date: dates[0], irrigation_in: 0.2)).not_to be_valid
    end

    it "keep no rain, and go once nothing is left in them" do
      entry = PlantingEntry.record(part.planting_entries, dates[1], {rain_in: 1.0, irrigation_in: nil, soil_moisture_pct: nil})
      expect(entry).to be_destroyed
      expect(part.planting_entries.reload).to be_empty
    end
  end

  it "counts a field growing only plots at its whole area for run hours" do
    plot
    irrigation = create(:pivot_irrigation, pivot:, date: Date.new(2026, 6, 1), inches: nil, run_hours: 10)
    expect(irrigation.irrigated_acres).to eq(10)
  end
end

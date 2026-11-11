require "rails_helper"

# PLAN.md Phase 8 G.9: a planting keeps its field's soil and area and its pivot's weather cell, so
# setup edits for a new season leave earlier seasons as they ran.
RSpec.describe "Season values on plantings" do
  let(:sand) { create(:soil_type, name: "Sand", field_capacity: 0.10, perm_wilting_pt: 0.04) }
  let(:loam) { create(:soil_type, name: "Loam", field_capacity: 0.30, perm_wilting_pt: 0.12) }
  let(:pivot) { create(:pivot, pump_capacity_gpm: 900) }
  let(:field) { create(:field, pivot:, soil_type: sand, area_acres: 60) }
  let!(:last_year) do
    create(:planting, field:, season_start: Date.new(2025, 4, 1), emergence_date: Date.new(2025, 5, 1),
      end_date: Date.new(2025, 9, 30))
  end
  let!(:this_year) { create(:planting, field:) } # Apr 1 – Sep 30, 2026

  around { |example| travel_to(Date.new(2026, 8, 1)) { example.run } }

  it "copies the field's soil, area and weather cell when a planting is created" do
    field.update_columns(field_capacity: 0.12)
    planting = create(:planting, field:, season_start: Date.new(2027, 4, 1), emergence_date: Date.new(2027, 5, 1),
      end_date: Date.new(2027, 9, 30))
    expect(planting).to have_attributes(soil_type: sand, field_capacity: 0.12, perm_wilting_pt: nil, area_acres: 60,
      weather_cell: pivot.weather_cell)
    expect(planting.effective_perm_wilting_pt).to eq(0.04)
  end

  it "starts a copied season from the field as it is now, not last season's values" do
    last_year.update!(soil_type: loam, area_acres: 45) # corrected for 2025 only
    SeasonCopy.new(field.pivot.farm.group, 2027).run
    copied = field.plantings.reload.find { |planting| planting.season_year == 2027 }
    expect(copied).to have_attributes(soil_type: sand, area_acres: 60)
  end

  it "keeps a planting's own soil type when it's given one" do
    planting = create(:planting, field:, soil_type: loam, season_start: Date.new(2027, 4, 1),
      emergence_date: Date.new(2027, 5, 1), end_date: Date.new(2027, 9, 30))
    expect(planting.soil_type).to eq(loam)
  end

  it "applies a field's new soil and area to seasons that haven't ended, not earlier ones" do
    field.update!(soil_type: loam, area_acres: 80, field_capacity: 0.32)
    expect(this_year.reload).to have_attributes(soil_type: loam, area_acres: 80, field_capacity: 0.32)
    expect(last_year.reload).to have_attributes(soil_type: sand, area_acres: 60, field_capacity: nil)
    expect(WaterBalance::Params.for(last_year).field_capacity).to eq(0.10)
    expect(WaterBalance::Params.for(this_year).field_capacity).to eq(0.32)
  end

  it "moves seasons that haven't ended with the pivot, and leaves earlier ones on their weather" do
    old_cell = pivot.weather_cell
    pivot.update!(latitude: 45.6, longitude: -91.2)
    expect(pivot.weather_cell).not_to eq(old_cell)
    expect(this_year.reload.weather_cell).to eq(pivot.weather_cell)
    expect(last_year.reload.weather_cell).to eq(old_cell)
  end

  it "keeps a field with earlier seasons on its pivot" do
    other = create(:pivot, farm: pivot.farm, latitude: 45.6, longitude: -91.2)
    expect(field.update(pivot: other)).to be(false)
    expect(field.errors[:pivot_id].first).to start_with("can't change for a field with earlier seasons")
  end

  it "moves a field without earlier seasons, its plantings following the new pivot's weather" do
    last_year.destroy!
    other = create(:pivot, farm: pivot.farm, latitude: 45.6, longitude: -91.2)
    expect(field.update(pivot: other)).to be(true)
    expect(this_year.reload.weather_cell).to eq(other.weather_cell)
  end

  it "counts a cell as active for this year's ended plantings after their pivot moved" do
    ended = create(:planting, field: create(:field, pivot:), season_start: Date.new(2026, 4, 1),
      emergence_date: Date.new(2026, 4, 20), end_date: Date.new(2026, 6, 30))
    old_cell = pivot.weather_cell
    pivot.update!(latitude: 45.6, longitude: -91.2)
    expect(ended.reload.weather_cell).to eq(old_cell)
    expect(WeatherCell.active).to include(old_cell, pivot.weather_cell)
    expect(old_cell.season_start(Date.new(2026, 8, 1))).to eq(Date.new(2026, 4, 1))
  end

  describe "run hours" do
    let(:neighbor) { create(:field, pivot:, soil_type: sand, area_acres: 60) }

    def irrigation(date) = create(:pivot_irrigation, pivot:, date:, inches: nil, run_hours: 10)

    it "spreads the water over the plantings in season that day, not fallow fields" do
      neighbor # no planting
      one = irrigation(Date.new(2026, 7, 1))
      expect(one.irrigated_acres).to eq(60)
      create(:planting, field: neighbor)
      two = irrigation(Date.new(2026, 7, 2))
      expect(two.irrigated_acres).to eq(120)
      expect(two.applied_inches).to be_within(0.0001).of(900 * 10 * 60 / (27_154.0 * 120))
    end

    it "uses each season's area, so a field changed for a later season doesn't move earlier irrigation" do
      earlier = irrigation(Date.new(2025, 7, 1))
      field.update!(area_acres: 120)
      expect(PivotIrrigation.find(earlier.id).irrigated_acres).to eq(60)
      expect(irrigation(Date.new(2026, 7, 1)).irrigated_acres).to eq(120)
    end

    it "counts the fields' areas on a day with no planting" do
      expect(irrigation(Date.new(2026, 3, 1)).irrigated_acres).to eq(60)
    end
  end
end

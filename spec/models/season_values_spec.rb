require "rails_helper"

# A planting keeps its field's soil and area, its system and that
# system's weather cell, so setup edits for a new season leave earlier seasons as they ran.
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
      pivot:, weather_cell: pivot.weather_cell)
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

  describe "a field moved to another system" do
    let(:other) { create(:pivot, farm: pivot.farm, latitude: 45.6, longitude: -91.2) }

    it "moves freely with earlier seasons, which keep their system and weather" do
      old_cell = pivot.weather_cell
      expect(field.update(pivot: other)).to be(true)
      expect(this_year.reload).to have_attributes(pivot: other, weather_cell: other.weather_cell)
      expect(last_year.reload).to have_attributes(pivot:, weather_cell: old_cell)
      expect(pivot.plantings).to eq([last_year])
    end

    it "lists irrigation under the system the field's season ran on (Pivot#irrigation_on)" do
      neighbor = create(:field, pivot:, name: "A neighbor")
      dates = [Date.new(2025, 7, 1), Date.new(2025, 7, 2), Date.new(2026, 7, 3), Date.new(2026, 7, 4)]
      field.field_entries.create!(date: dates[0], irrigation_in: 0.8)
      neighbor.field_entries.create!(date: dates[0], irrigation_in: 0.7)
      field.field_entries.create!(date: dates[1], rain_in: 0.5) # no irrigation
      field.update!(pivot: other)
      field.field_entries.create!(date: dates[2], irrigation_in: 0.6)
      neighbor.field_entries.create!(date: dates[3], irrigation_in: 0.9)

      old = pivot.irrigation_on(dates)
      expect(old.keys).to eq([dates[0], dates[3]])
      expect(old[dates[0]].transform_values(&:irrigation_in)).to eq(neighbor => 0.7, field => 0.8)
      expect(old[dates[0]].keys).to eq([neighbor, field]) # by name
      expect(old[dates[3]].transform_values(&:irrigation_in)).to eq(neighbor => 0.9)
      expect(other.irrigation_on(dates).transform_values { |fields| fields.transform_values(&:irrigation_in) })
        .to eq(dates[2] => {field => 0.6})
      expect(pivot.irrigation_on(dates[1]..dates[2])).to eq({})

      # Each season's balance takes the field's own irrigation, whichever system it ran on
      earlier = PlantingBalance.new(last_year.reload, weather: {}).days.to_h { |day| [day.inputs.date, day.inputs] }
      expect(earlier[dates[0]]).to have_attributes(irrigation: 0.8, irrigation_source: :entered)
      expect(earlier[dates[1]]).to have_attributes(irrigation: 0.0, irrigation_source: :none)
      now = PlantingBalance.new(this_year.reload, weather: {}).days.to_h { |day| [day.inputs.date, day.inputs] }
      expect(now[dates[2]]).to have_attributes(irrigation: 0.6, irrigation_source: :entered)
    end

    it "lists the field under each system on the days its seasons ran there" do
      field.update!(pivot: other)
      expect(pivot.fields_on(Date.new(2025, 7, 1))).to eq([field])
      expect(other.fields_on(Date.new(2025, 7, 1))).to eq([])
      expect(pivot.fields_on(Date.new(2026, 7, 1))).to eq([])
      expect(other.fields_on(Date.new(2026, 7, 1))).to eq([field])
    end

    it "hands its seasons to the field's system when the old system is deleted" do
      field.update!(pivot: other)
      pivot.destroy!
      expect(last_year.reload.pivot).to eq(other)
    end
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
end

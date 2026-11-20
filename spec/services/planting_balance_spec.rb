require "rails_helper"

RSpec.describe PlantingBalance do
  let(:soil_type) { create(:soil_type, field_capacity: 0.15, perm_wilting_pt: 0.05) }
  let(:field) { create(:field, soil_type:) }
  let(:planting) do
    create(:planting, field:, season_start: Date.new(2026, 6, 1), emergence_date: Date.new(2026, 6, 1),
      end_date: Date.new(2026, 6, 10), max_root_zone_depth: 24, mad_frac: 0.5)
  end
  let(:weather) { (planting.season_start..planting.end_date).to_h { |d| [d, {et0: 0.2, precip: 0.0}] } }

  it "runs the season from the planting, its field's entries and the weather" do
    create(:canopy_observation, planting:, date: Date.new(2026, 6, 5), pct_cover: 100)
    create(:field_entry, field:, date: Date.new(2026, 6, 6), irrigation_in: 0.5)

    days = described_class.new(planting, weather:).days
    expect(days.size).to eq(10)
    expect(days.map(&:canopy).first(6)).to eq([0.0, 25.0, 50.0, 75.0, 100.0, 100.0])
    expect(days[5].inputs).to have_attributes(irrigation: 0.5, irrigation_source: :entered)
    expect(days.last.result.ad).to be < 1.2
    expect(days.last.result.ad).to eq(WaterBalance.run(described_class.new(planting).params, days.map { |d|
      WaterBalance::Day.new(date: d.inputs.date, et0: 0.2, rain: 0.0, irrigation: d.inputs.irrigation, canopy: d.canopy)
    }).last.ad)
  end

  describe "with the crop's dual coefficient (C22)" do
    before { planting.plant.update!(kcb_mid: 1.10, kcb_end: 0.65, crop_height_m: 0.6) }

    it "takes Kcb mid at full cover, adjusted for the day's wind and humidity" do
      create(:canopy_observation, planting:, date: Date.new(2026, 6, 2), pct_cover: 100)
      calm = weather.transform_values { |values| values.merge(wind: nil, rh_min: nil) }
      dry = weather.transform_values { |values| values.merge(wind: 15.0, rh_min: 25.0) }

      # Four days without rain have dried the surface: no evaporation (Ke 0)
      expect(described_class.new(planting, weather: calm).days[4].result.adj_et).to be_within(1e-4).of(0.2 * 1.10)
      windy = described_class.new(planting, weather: dry).days[4]
      expect(windy.inputs).to have_attributes(wind_mph: 15.0, rh_min_pct: 25.0)
      kcb = CropEt.kc_mid(1.10, 0.6, wind_mph: 15.0, rh_min_pct: 25.0)
      expect(windy.result.adj_et).to be_within(1e-4).of(0.2 * kcb)
      expect(windy.result.adj_et).to be > 0.2 * 1.10
    end

    it "evaporates from the wet bare soil before emergence's canopy, then less as it dries" do
      planting.update!(emergence_date: Date.new(2026, 6, 20), end_date: Date.new(2026, 6, 30))
      days = described_class.new(planting, weather:).days
      expect(days.first.result.adj_et).to be_within(1e-4).of(0.2 * 1.2)
      expect(days.map { |day| day.result.adj_et }.first(10).each_cons(2)).to all(satisfy { |a, b| b <= a })
      expect(days[9].result.evaporation.depletion).to be > days[0].result.evaporation.depletion
    end

    it "takes the soil's readily evaporable water and the irrigation system's wetted fraction" do
      soil_type.update!(rew_in: 0.2)
      planting.pivot.update!(kind: "drip")
      params = described_class.new(planting.reload).params
      expect(params).to have_attributes(rew: 0.2, irrigation_fw: 0.35)
      expect(params.evaporation.tew).to be_within(1e-9).of((0.15 - 0.025) / 0.254)
      expect(params.crop).to have_attributes(kcb_mid: 1.10, kcb_end: 0.65, end_date: planting.end_date)
    end
  end

  it "reads wind and minimum humidity from stored days and the forecast" do
    cell = field.pivot.reload.weather_cell
    cell.weather_days.create!(date: Date.new(2026, 6, 1), et0_in: 0.2, precip_in: 0.0, wind_speed_mph: 9.0, rh_min_pct: 40.0,
      model: "best_match", hours: 24, fetched_at: Time.current)
    inputs = WeatherDay.balance_inputs(cell, [Date.new(2026, 6, 1)])
    expect(inputs[Date.new(2026, 6, 1)]).to include(wind: 9.0, rh_min: 40.0)
  end

  it "uses the field's own water fractions over the soil type's" do
    field.update!(field_capacity: 0.2)
    expect(described_class.new(planting).params.field_capacity).to eq(0.2)
  end

  it "uses the stored weather for the field's cell by default" do
    cell = field.pivot.reload.weather_cell
    weather.each do |date, values|
      cell.weather_days.create!(date:, et0_in: values[:et0], precip_in: values[:precip], model: "best_match", hours: 24,
        fetched_at: Time.current)
    end
    cell.weather_days.find_by(date: Date.new(2026, 6, 10)).destroy!
    days = described_class.new(planting).days
    expect(days.first.inputs).to have_attributes(et0: 0.2, et0_source: :model, rain_source: :model)
    expect(days.last.inputs).to have_attributes(et0: nil, et0_source: :missing, rain: nil)
  end

  it "stops at the given date" do
    expect(described_class.new(planting, weather:).days(through: Date.new(2026, 6, 3)).size).to eq(3)
  end
end

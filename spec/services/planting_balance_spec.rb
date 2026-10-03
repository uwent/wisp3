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

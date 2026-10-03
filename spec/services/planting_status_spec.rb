require "rails_helper"

RSpec.describe PlantingStatus do
  let(:group) { create(:group) }
  let(:field) { create(:field, pivot: create(:pivot, farm: create(:farm, group:))) }
  let(:planting) do
    create(:planting, field:, season_start: Date.new(2026, 7, 1), emergence_date: Date.new(2026, 7, 1),
      end_date: Date.new(2026, 7, 31))
  end
  # FC 0.15, PWP 0.05, MRZD 24 in, MAD 0.5: AD_max 1.2 in
  let(:weather) do
    (Date.new(2026, 7, 1)..Date.new(2026, 7, 31)).to_h { |date| [date, {et0: 0.2, precip: (date.day == 3) ? 0.5 : 0.0}] }
  end

  def status(today) = described_class.new(planting, today:, weather:)

  it "knows where today falls in the season" do
    expect(status(Date.new(2026, 6, 30))).to have_attributes(phase: :upcoming, days: [], current: nil, status: nil)
    expect(status(Date.new(2026, 7, 10)).phase).to eq(:active)
    expect(status(Date.new(2026, 8, 15))).to have_attributes(phase: :ended)
    expect(status(Date.new(2026, 8, 15)).current.inputs.date).to eq(Date.new(2026, 7, 31))
  end

  it "runs the balance through today and gives today's status" do
    today = status(Date.new(2026, 7, 10))
    expect(today.days.size).to eq(10)
    expect(today.status).to eq(WaterBalance.status(today.params, today.current.result.ad))
  end

  it "finds the latest rain and irrigation" do
    field.field_entries.create!(date: Date.new(2026, 7, 6), irrigation_in: 0.6)
    today = status(Date.new(2026, 7, 10))
    expect(today.last_rain.inputs).to have_attributes(date: Date.new(2026, 7, 3), rain: 0.5)
    expect(today.last_irrigation.inputs).to have_attributes(date: Date.new(2026, 7, 6), irrigation: 0.6)
  end

  it "totals the season and sets entered rain against the model's for the same days (Q7)" do
    field.field_entries.create!(date: Date.new(2026, 7, 3), rain_in: 0.8)
    field.field_entries.create!(date: Date.new(2026, 7, 4), rain_in: 0.0)
    totals = status(Date.new(2026, 7, 10)).totals
    expect(totals).to have_attributes(rain: 0.8, rain_model: 0.5, entered_rain_days: 2, entered_rain: 0.8,
      entered_rain_model: 0.5, irrigation: 0.0)
    expect(totals.adj_et).to be > 0
  end
end

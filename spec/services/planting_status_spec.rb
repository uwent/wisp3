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

  it "knows when the season has started but no weather has arrived" do
    expect(status(Date.new(2026, 7, 10)).weather_pending?).to be(false)
    expect(status(Date.new(2026, 6, 30)).weather_pending?).to be(false)
    expect(described_class.new(planting, today: Date.new(2026, 7, 10), weather: {}).weather_pending?).to be(true)
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

RSpec.describe PlantingStatus, "projection" do
  let(:field) { create(:field, pivot: create(:pivot)) }
  # FC 0.15, PWP 0.05, MRZD 24 in, MAD 0.5: AD_max 1.2 in, AD 0 at the trigger. 80% cover from
  # emergence, so adjusted ET = et0.
  let(:planting) do
    create(:planting, field:, season_start: Date.new(2026, 7, 1), emergence_date: Date.new(2026, 7, 1),
      end_date: Date.new(2026, 8, 31)).tap { |p| p.canopy_observations.create!(date: Date.new(2026, 7, 1), pct_cover: 80) }
  end
  let(:today) { Date.new(2026, 7, 10) }
  # Observed through yesterday, then the forecast from today: 0.1 in/day of ET throughout
  let(:weather) do
    (Date.new(2026, 7, 1)..today + 15).to_h { |date| [date, {et0: 0.1, precip: 0.0, forecast: date >= today}] }
  end

  def status(ensemble: [], weather: self.weather) = described_class.new(planting, today:, weather:, ensemble:)

  it "projects the balance through the forecast, after today" do
    projection = status
    expect(projection.days.last.inputs).to have_attributes(date: today, et0_source: :forecast, rain_source: :forecast)
    expect(projection.forecast_days.map { |day| day.inputs.date }).to eq((today + 1..today + 15).to_a)
    # 1.2 in at the start, 0.1 a day: 0.2 left after today, 0 two days later
    expect(projection.current.result.ad).to eq(0.2)
    expect(projection.crossing).to have_attributes(date: today + 2, days: 2, ad: 0.0, refill: 1.2)
  end

  it "makes a field that's fine today caution when it reaches the threshold within 3 days" do
    expect(status.status).to eq(:caution)
    planting.update!(target_ad_pct: 50) # target 0.6 in, already crossed
    expect(status.crossing).to have_attributes(date: today, days: 0)
  end

  it "counts planned irrigation (an entry on a future date)" do
    field.field_entries.create!(date: today + 1, irrigation_in: 1.0)
    projection = status
    expect(projection.crossing.date).to eq(today + 12) # 1.1 in after tomorrow, 0.1 a day
  end

  it "stops where the forecast ends, and at the season's end" do
    short = weather.reject { |date, _| date > today + 5 }
    expect(status(weather: short).forecast_days.size).to eq(5)
    planting.update!(end_date: today + 3)
    expect(status.forecast_days.size).to eq(3)
  end

  it "has no projection before or after the season" do
    expect(described_class.new(planting, today: Date.new(2026, 6, 1), weather:, ensemble: []).forecast_days).to be_empty
    ended = described_class.new(planting, today: Date.new(2026, 9, 15), weather:, ensemble: [])
    expect([ended.forecast_days, ended.crossing]).to eq([[], nil])
  end

  describe "ensemble" do
    # Three members over the 15 days ahead: dry and hot, the same as the forecast, and 1 in of rain tomorrow
    let(:members) do
      dates = (today + 1..today + 15)
      [
        dates.to_h { |date| [date, {et0: 0.2, precip: 0.0}] },
        dates.to_h { |date| [date, {et0: 0.1, precip: 0.0}] },
        dates.to_h { |date| [date, {et0: 0.1, precip: (date == today + 1) ? 1.0 : 0.0}] }
      ]
    end

    it "gives the range of AD and the chance of reaching the threshold by each day" do
      bands = status(ensemble: members).ensemble
      expect(bands.size).to eq(15)
      tomorrow = bands.first
      expect(tomorrow.date).to eq(today + 1)
      expect([tomorrow.p50, tomorrow.chance]).to eq([0.1, 0.33]) # the hot member is at 0
      expect(bands[1].chance).to eq(0.67) # the forecast member too
      expect(bands.last.chance).to eq(1.0) # rain only delays the third
      expect(bands.first.p90).to be > bands.first.p10
    end

    it "keeps entered values in every member" do
      field.field_entries.create!(date: today + 1, irrigation_in: 1.0, rain_in: 0.0)
      bands = status(ensemble: members).ensemble
      expect(bands.first.chance).to eq(0.0)
    end

    it "counts every member as crossed when today already is" do
      planting.update!(target_ad_pct: 50)
      expect(status(ensemble: members).ensemble.first.chance).to eq(1.0)
    end
  end

  it "takes today's weather from the forecast when the cell has one" do
    cell = field.pivot.weather_cell || field.pivot.tap(&:save!).weather_cell
    cell.weather_forecasts.create!(issued_at: Time.current, model: "best_match",
      payload: {days: (today..today + 15).map { |date| {date: date.iso8601, et0_in: 0.15, precip_in: 0.0} }})
    (Date.new(2026, 7, 1)...today).each do |date|
      cell.weather_days.create!(date:, model: "best_match", hours: 24, fetched_at: Time.current, et0_in: 0.1, precip_in: 0.0)
    end
    projection = described_class.new(planting, today:, ensemble: [])
    expect(projection.current.inputs).to have_attributes(et0: 0.15, et0_source: :forecast)
    expect(projection.forecast_days.size).to eq(15)
  end
end

RSpec.describe EnsembleProjection do
  it "interpolates percentiles" do
    expect(described_class.percentile([4, 1, 3, 2, 5], 0.5)).to eq(3)
    expect(described_class.percentile([1, 2], 0.1)).to eq(1.1)
  end
end

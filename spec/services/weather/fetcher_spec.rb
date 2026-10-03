require "rails_helper"

RSpec.describe Weather::Fetcher do
  let(:today) { Date.new(2026, 7, 20) }
  let(:client) { FakeOpenMeteo.new(today:) }
  let(:fetcher) { described_class.new(client:, models: %w[best_match]) }
  let(:cell) { WeatherCell.for(44.12, -89.53) }

  around { |example| travel_to(Time.zone.parse("2026-07-20 12:00")) { example.run } }

  describe "#refresh" do
    it "stores the past week and a 16-day forecast, from the primary and soil models" do
      fetcher.refresh([cell])
      expect(client.calls.map { |call| call[:model] }).to eq(%w[best_match ecmwf_ifs])
      expect(cell.weather_days.order(:date).pluck(:date)).to eq((today - 7..today - 1).to_a)

      day = cell.weather_days.last
      expect(day).to have_attributes(model: "best_match", soil_model: "ecmwf_ifs", hours: 24, final: false, tmean_f: 50.0,
        soil_moisture_0_7cm: 0.3)
      expect(day.et0_in).to be_within(1e-9).of(24 * 0.2 / 25.4)

      forecast = cell.latest_forecast
      expect(forecast.days.keys).to eq((today..today + 15).to_a)
      expect(forecast.days[today]["soil_moisture_0_7cm"]).to eq(0.3)
      expect(cell.reload).to have_attributes(timezone: "America/Chicago", elevation_m: 300.0, last_error: nil)
    end

    it "updates provisional days but leaves final ones alone" do
      fetcher.refresh([cell])
      cell.weather_days.find_by(date: today - 7).update!(final: true, et0_in: 9.0)
      described_class.new(client: FakeOpenMeteo.new(today:, et0_mm: 0.4), models: %w[best_match]).refresh([cell])
      expect(cell.weather_days.find_by(date: today - 7).et0_in).to eq(9.0)
      expect(cell.weather_days.find_by(date: today - 1).et0_in).to be_within(1e-9).of(24 * 0.4 / 25.4)
    end

    it "records an error on the cells and re-raises it" do
      failing = Object.new
      def failing.hourly(*, **) = raise(Weather::TransientError, "Open-Meteo 503")
      expect { described_class.new(client: failing).refresh([cell]) }.to raise_error(Weather::TransientError)
      expect(cell.reload.last_error).to eq("Open-Meteo 503")
    end
  end

  it "asks each primary model in turn, then the soil model" do
    described_class.new(client:, models: %w[ncep_nbm_conus best_match]).refresh([cell])
    expect(client.calls.map { |call| call[:model] }).to eq(%w[ncep_nbm_conus best_match ecmwf_ifs])
    expect(cell.weather_days.first.model).to eq("ncep_nbm_conus,best_match")
  end

  describe "#backfill" do
    it "fetches only missing runs from the historical-forecast API, in chunks" do
      fetcher.refresh([cell]) # the last week
      stored = fetcher.backfill(cell, from: Date.new(2026, 4, 1))
      expect(stored).to eq((Date.new(2026, 4, 1)..today - 8).count)
      historical = client.calls.select { |call| call[:endpoint] == :historical_forecast && call[:model] == "best_match" }
      expect(historical.map { |call| [call[:start_date], call[:end_date]] }).to eq([
        [Date.new(2026, 4, 1), Date.new(2026, 7, 1)], [Date.new(2026, 7, 2), today - 8]
      ])
      expect(fetcher.missing_runs(cell, Date.new(2026, 4, 1), today - 1)).to be_empty
      expect(cell.weather_forecasts.count).to eq(1) # backfills don't make forecasts
      expect(cell.weather_days.where(final: false).pluck(:date)).to all(be >= today - 7)
    end
  end
end

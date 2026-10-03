require "rails_helper"

RSpec.describe "Weather jobs" do
  let(:cell) { WeatherCell.for(44.12, -89.53) }

  around { |example| travel_to(Time.zone.parse("2026-07-20 12:00")) { example.run } }

  describe Pivot do
    it "gets its weather cell, and a backfill, when created or moved" do
      pivot = nil
      expect { pivot = create(:pivot, latitude: 44.12, longitude: -89.53) }.to have_enqueued_job(WeatherBackfillJob)
      expect(pivot.weather_cell).to have_attributes(latitude: be_within(1e-5).of(44.112477), longitude: be_within(1e-5).of(-89.589041))

      expect { pivot.update!(name: "Renamed", latitude: 44.121) }.not_to have_enqueued_job(WeatherBackfillJob) # same cell
      expect { pivot.update!(latitude: 44.5) }.to have_enqueued_job(WeatherBackfillJob)
      expect(WeatherCell.count).to eq(2)
    end
  end

  describe WeatherCell do
    it "is active while a planting on one of its pivots is in this season" do
      field = create(:field, pivot: create(:pivot, latitude: 44.12, longitude: -89.53))
      expect(WeatherCell.active).to be_empty
      create(:planting, field:, season_start: Date.new(2026, 4, 1), end_date: Date.new(2026, 9, 30))
      expect(WeatherCell.active).to eq([field.pivot.weather_cell])
      expect(field.pivot.weather_cell.season_start).to eq(Date.new(2026, 4, 1))
    end
  end

  describe WeatherRefreshJob do
    it "refreshes active cells, then queues a backfill for each" do
      create(:planting, field: create(:field, pivot: create(:pivot, latitude: 44.12, longitude: -89.53)))
      fetcher = instance_double(Weather::Fetcher, refresh: nil)
      allow(Weather::Fetcher).to receive(:new).and_return(fetcher)
      expect { described_class.perform_now }.to have_enqueued_job(WeatherBackfillJob).with(WeatherCell.sole.id)
      expect(fetcher).to have_received(:refresh).with([WeatherCell.sole])
    end
  end

  describe WeatherBackfillJob do
    it "fills from the season start, or the last 30 days" do
      fetcher = instance_double(Weather::Fetcher, backfill: 0)
      allow(Weather::Fetcher).to receive(:new).and_return(fetcher)
      described_class.perform_now(cell.id)
      expect(fetcher).to have_received(:backfill).with(cell, from: Date.new(2026, 6, 20))
    end
  end

  describe WeatherFinalizeJob do
    it "makes days more than a week old final" do
      [Date.new(2026, 7, 12), Date.new(2026, 7, 13)].each do |date|
        cell.weather_days.create!(date:, model: "best_match", hours: 24, fetched_at: Time.current)
      end
      described_class.perform_now
      expect(cell.weather_days.order(:date).pluck(:final)).to eq([true, false])
    end
  end

  describe ForecastPruneJob do
    it "keeps each cell's latest 14 forecasts" do
      other = WeatherCell.for(36.7, -119.8)
      20.times { |i| cell.weather_forecasts.create!(issued_at: i.hours.ago, model: "best_match", payload: {days: []}) }
      3.times { |i| other.weather_forecasts.create!(issued_at: i.hours.ago, model: "best_match", payload: {days: []}) }
      described_class.perform_now
      expect(cell.weather_forecasts.count).to eq(14)
      expect(cell.weather_forecasts.minimum(:issued_at)).to be > 14.hours.ago
      expect(other.weather_forecasts.count).to eq(3)
    end
  end

  it "retries Open-Meteo outages" do
    allow(Weather::Fetcher).to receive(:new).and_raise(Weather::TransientError, "503")
    expect { WeatherBackfillJob.perform_now(cell.id) }.to have_enqueued_job(WeatherBackfillJob)
  end
end

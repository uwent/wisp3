require "rails_helper"

RSpec.describe "Weather jobs" do
  let(:cell) { WeatherCell.for(44.12, -89.53) }

  around { |example| travel_to(Time.zone.parse("2026-07-20 12:00")) { example.run } }

  describe Pivot do
    it "gets its weather cell, and a weather update, when created or moved" do
      pivot = nil
      expect { pivot = create(:pivot, latitude: 44.12, longitude: -89.53) }.to have_enqueued_job(WeatherUpdateJob)
      expect(pivot.weather_cell).to have_attributes(latitude: be_within(1e-5).of(44.112477), longitude: be_within(1e-5).of(-89.589041))

      expect { pivot.update!(name: "Renamed", latitude: 44.121) }.not_to have_enqueued_job(WeatherUpdateJob) # same cell
      expect { pivot.update!(latitude: 44.5) }.to have_enqueued_job(WeatherUpdateJob)
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

    it "is active out of season for a digest that shows its pivots' weather then" do
      user = create(:user, digest_frequency: "daily")
      field = create(:field, pivot: create(:pivot, latitude: 44.12, longitude: -89.53, farm: create(:farm, group: user.groups.first)))
      expect(WeatherCell.active).to be_empty
      user.update!(digest_frequency: "daily_all_year")
      expect(WeatherCell.active).to eq([field.pivot.weather_cell])
      user.update!(digest_frequency: "daily", digest_scope: "all")
      expect(WeatherCell.active).to eq([field.pivot.weather_cell])
      user.update!(digest_frequency: "never")
      expect(WeatherCell.active).to be_empty
    end

    it "queues an update for cells being looked at, at most every 15 minutes each" do
      other = WeatherCell.for(36.7, -119.8)
      expect { WeatherCell.keep_current([cell.id, nil, cell.id]) }.to have_enqueued_job(WeatherUpdateJob).with(cell.id, quiet: false).exactly(:once)
      expect { WeatherCell.keep_current([cell.id, other.id]) }.to have_enqueued_job(WeatherUpdateJob).with(other.id, quiet: false).exactly(:once)
      travel 16.minutes
      expect { WeatherCell.keep_current([cell.id]) }.to have_enqueued_job(WeatherUpdateJob).with(cell.id, quiet: false)
    end

    it "shows an update only when the cell's weather is incomplete: no recent forecast, or days missing" do
      (Date.new(2026, 6, 19)..Date.new(2026, 7, 19)).each do |date|
        cell.weather_days.create!(date:, et0_in: 0.2, precip_in: 0, model: "ncep_nbm_conus", hours: 24, fetched_at: Time.current)
      end
      expect(cell).to be_incomplete # no forecast
      forecast = cell.weather_forecasts.create!(issued_at: 25.hours.ago, model: "best_match", payload: {days: []})
      expect(cell).to be_incomplete
      forecast.update!(issued_at: 5.hours.ago) # stale, but recent enough to show
      expect(cell).not_to be_incomplete
      expect { WeatherCell.keep_current([cell.id]) }.to have_enqueued_job(WeatherUpdateJob).with(cell.id, quiet: true)
      expect(WeatherCell.updating_ids([cell.id])).to be_empty

      cell.weather_days.find_by(date: Date.new(2026, 7, 1)).destroy
      expect(cell).to be_incomplete
      create(:planting, field: create(:field, pivot: create(:pivot, latitude: 44.12, longitude: -89.53)),
        season_start: Date.new(2026, 5, 1), end_date: Date.new(2026, 9, 30))
      cell.weather_days.create!(date: Date.new(2026, 7, 1), et0_in: 0.2, precip_in: 0, model: "ncep_nbm_conus", hours: 24, fetched_at: Time.current)
      expect(cell).to be_incomplete # the season starts May 1
    end

    it "has a stale forecast when it has none, or none in the last 3 hours" do
      expect(cell).to be_forecast_stale
      cell.weather_forecasts.create!(issued_at: 4.hours.ago, model: "best_match", payload: {days: []})
      expect(cell).to be_forecast_stale
      cell.weather_forecasts.create!(issued_at: 2.hours.ago, model: "best_match", payload: {days: []})
      expect(cell).not_to be_forecast_stale
    end
  end

  describe WeatherRefreshJob do
    it "refreshes active cells and their ensembles, then queues a backfill for each" do
      create(:planting, field: create(:field, pivot: create(:pivot, latitude: 44.12, longitude: -89.53)))
      fetcher = instance_double(Weather::Fetcher, refresh: nil, refresh_ensemble: 0)
      allow(Weather::Fetcher).to receive(:new).and_return(fetcher)
      expect { described_class.perform_now }.to have_enqueued_job(WeatherBackfillJob).with(WeatherCell.sole.id)
      expect(fetcher).to have_received(:refresh).with([WeatherCell.sole])
      expect(fetcher).to have_received(:refresh_ensemble).with([WeatherCell.sole])
    end

    it "refreshes every cell with a pivot when asked for all" do
      create(:pivot, latitude: 44.12, longitude: -89.53)
      WeatherCell.for(36.7, -119.8) # no pivot
      fetcher = instance_double(Weather::Fetcher, refresh: nil, refresh_ensemble: 0)
      allow(Weather::Fetcher).to receive(:new).and_return(fetcher)
      described_class.perform_now
      expect(fetcher).to have_received(:refresh).with([])
      described_class.perform_now(all: true)
      expect(fetcher).to have_received(:refresh).with([WeatherCell.find_by!(pivots: Pivot.all)])
    end
  end

  describe WeatherUpdateJob do
    let(:fetcher) { instance_double(Weather::Fetcher, refresh: nil, refresh_ensemble: 0, backfill: 0) }

    before { allow(Weather::Fetcher).to receive(:new).and_return(fetcher) }

    it "refreshes a stale cell, active or not, then fills its gaps" do
      described_class.perform_now(cell.id)
      expect(fetcher).to have_received(:refresh).with([cell])
      expect(fetcher).to have_received(:refresh_ensemble).with([cell])
      expect(fetcher).to have_received(:backfill).with(cell, from: Date.new(2026, 6, 20))
    end

    it "marks its cell as updating from when it's queued until it ends, failed or not" do
      other = WeatherCell.for(45.5, -90.5)
      expect(WeatherCell.updating_ids([cell.id, other.id])).to be_empty
      described_class.perform_later(cell.id)
      expect(WeatherCell.updating_ids([cell.id, other.id, nil])).to eq([cell.id])

      described_class.perform_now(cell.id)
      expect(WeatherCell.updating_ids([cell.id])).to be_empty

      described_class.perform_later(cell.id)
      allow(fetcher).to receive(:backfill).and_raise(ArgumentError)
      expect { described_class.perform_now(cell.id) }.to raise_error(ArgumentError)
      expect(WeatherCell.updating_ids([cell.id])).to be_empty
    end

    it "leaves its cell unmarked when quiet, and a shown update's mark alone" do
      described_class.perform_later(cell.id, quiet: true)
      expect(WeatherCell.updating_ids([cell.id])).to be_empty
      described_class.perform_later(cell.id)
      described_class.perform_now(cell.id, quiet: true)
      expect(WeatherCell.updating_ids([cell.id])).to eq([cell.id])
    end

    it "skips the refresh when the forecast is fresh, and the ensemble likewise" do
      cell.weather_forecasts.create!(issued_at: 1.hour.ago, model: "best_match", payload: {days: []})
      described_class.perform_now(cell.id)
      expect(fetcher).not_to have_received(:refresh)
      expect(fetcher).to have_received(:refresh_ensemble) # its ensemble is still stale
      expect(fetcher).to have_received(:backfill)

      cell.weather_forecasts.create!(kind: "ensemble", issued_at: 1.hour.ago, model: "gfs_seamless", payload: {dates: [], members: []})
      fresh = instance_double(Weather::Fetcher, refresh: nil, refresh_ensemble: 0, backfill: 0)
      allow(Weather::Fetcher).to receive(:new).and_return(fresh)
      described_class.perform_now(cell.id)
      expect(fresh).not_to have_received(:refresh_ensemble)
      expect(fresh).to have_received(:backfill)
    end

    it "does nothing for a cell that's gone" do
      described_class.perform_now(0)
      expect(Weather::Fetcher).not_to have_received(:new)
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

  describe WeatherRecorrectJob do
    it "refetches the cell's days through the current corrections" do
      fetcher = instance_double(Weather::Fetcher, recorrect: 0)
      allow(Weather::Fetcher).to receive(:new).and_return(fetcher)
      described_class.perform_now(cell.id)
      expect(fetcher).to have_received(:recorrect).with(cell)
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
    it "keeps each cell's latest 14 forecasts of each kind" do
      other = WeatherCell.for(36.7, -119.8)
      20.times { |i| cell.weather_forecasts.create!(issued_at: i.hours.ago, model: "best_match", payload: {days: []}) }
      cell.weather_forecasts.create!(kind: "ensemble", issued_at: 30.hours.ago, model: "gfs_seamless", payload: {dates: [], members: []})
      3.times { |i| other.weather_forecasts.create!(issued_at: i.hours.ago, model: "best_match", payload: {days: []}) }
      described_class.perform_now
      expect(cell.weather_forecasts.deterministic.count).to eq(14)
      expect(cell.weather_forecasts.deterministic.minimum(:issued_at)).to be > 14.hours.ago
      expect(cell.weather_forecasts.ensemble.count).to eq(1)
      expect(other.weather_forecasts.count).to eq(3)
    end

    it "keeps each cell's first corrected issue of each kind on each local day for good" do
      corrected = {days: [{date: "2026-07-01", corrections: ["et0-fao56 v1"]}]}
      # Three a day for ten days, the 5 am (Central) one first; the first five days' uncorrected
      10.times do |d|
        [5, 11, 17].each do |hour|
          issued_at = Time.find_zone("America/Chicago").local(2026, 7, 1 + d, hour)
          payload = (d < 5) ? {days: [{date: "2026-07-01", corrections: []}]} : corrected
          cell.weather_forecasts.create!(issued_at:, model: "m", payload:)
          cell.weather_forecasts.create!(kind: "ensemble", issued_at:, model: "gfs_seamless",
            payload: {dates: [], members: [], **((d < 5) ? {} : {corrections: ["et0-ensemble-ratio v1"]})})
        end
      end
      cell.update!(timezone: "America/Chicago")
      described_class.perform_now
      %w[deterministic ensemble].each do |kind|
        kept = cell.weather_forecasts.where(kind:)
        # The latest 14 (July 7-10, and July 6's 11 am and 5 pm), July 6's 5 am issue for good, none uncorrected
        expect(kept.count).to eq(15)
        expect(kept.where(issued_at: Time.find_zone("America/Chicago").local(2026, 7, 6, 5))).to exist
        expect(kept.where(issued_at: ...Time.find_zone("America/Chicago").local(2026, 7, 6))).not_to exist
      end
    end
  end

  it "counts weather jobs queued or running" do
    allow(Weather::Fetcher).to receive(:new).and_return(instance_double(Weather::Fetcher, backfill: 0))
    WeatherBackfillJob.perform_later(cell.id)
    WeatherBackfillJob.perform_later(cell.id)
    expect(WeatherJob.pending).to eq(2)
    perform_enqueued_jobs
    expect(WeatherJob.pending).to eq(0)
    WeatherBackfillJob.perform_now(cell.id) # never queued, so never counted
    expect(WeatherJob.pending).to eq(0)
  end

  it "retries Open-Meteo outages" do
    allow(Weather::Fetcher).to receive(:new).and_raise(Weather::TransientError, "503")
    expect { WeatherBackfillJob.perform_now(cell.id) }.to have_enqueued_job(WeatherBackfillJob)
  end
end

require "rails_helper"

RSpec.describe HealthCheck do
  let(:now) { Time.zone.local(2026, 7, 20, 7) }
  let(:check) { described_class.new(now:) }
  let(:field) { create(:field, pivot: create(:pivot, latitude: 44.12, longitude: -89.53)) }
  let(:cell) { field.pivot.reload.weather_cell }

  around { |example| travel_to(now) { example.run } }

  # An active cell with the last week's weather, and a forecast from this morning
  def current_cell
    create(:planting, field:, season_start: Date.new(2026, 7, 1), end_date: Date.new(2026, 9, 30))
    (Date.new(2026, 7, 13)..Date.new(2026, 7, 19)).each do |date|
      cell.weather_days.create!(date:, et0_in: 0.2, precip_in: 0, model: "best_match", hours: 24, fetched_at: 2.hours.ago)
    end
    cell.weather_forecasts.create!(issued_at: 2.hours.ago, model: "best_match", payload: {days: []})
    cell
  end

  def problem(kind) = check.problems.find { |problem| problem.kind == kind }

  it "finds nothing wrong when the weather is complete and no job failed" do
    current_cell
    expect(check.problems).to eq([])
  end

  describe "failed jobs" do
    it "groups those since the last check by class, with counts and the latest error's first line" do
      allow(check).to receive(:failed_executions).and_return([
        ["WeatherUpdateJob", "Weather::TransientError", "Open-Meteo 503", 5.hours.ago],
        ["WeatherUpdateJob", "Weather::TransientError", "Open-Meteo 502\nretry later", 2.hours.ago],
        ["DailyDigestJob", "DailyDigestJob::Incomplete", "1 of 9 daily emails failed", 1.hour.ago]
      ])
      failed = problem(:failed_jobs)
      expect(failed.summary).to eq("3 jobs failed since the last check")
      expect(failed.details).to eq([
        "WeatherUpdateJob: 2 failed, latest 2 h ago: Weather::TransientError: Open-Meteo 502",
        "DailyDigestJob: 1 failed, latest 1 h ago: DailyDigestJob::Incomplete: 1 of 9 daily emails failed"
      ])
    end

    it "says a job failed under an hour ago, and leaves out an error it doesn't have" do
      allow(check).to receive(:failed_executions).and_return([["WeatherBackfillJob", nil, nil, 10.minutes.ago]])
      expect(problem(:failed_jobs).details).to eq(["WeatherBackfillJob: 1 failed, latest under an hour ago"])
    end

    it "reads Solid Queue's failed executions since the last check, with the error from its JSON column" do
      allow(described_class).to receive(:solid_queue?).and_return(true)
      failed = double(job: double(class_name: "WeatherUpdateJob"), created_at: 2.hours.ago,
        error: {"exception_class" => "Weather::TransientError", "message" => "Open-Meteo 503", "backtrace" => []})
      no_error = double(job: double(class_name: "DailyDigestJob"), created_at: 1.hour.ago, error: nil)
      # Its tables exist only in the servers' queue database: a relation that takes any scoping and
      # yields these rows, checked only for the time window
      relation = Class.new(Array) do
        attr_reader :window
        def includes(*) = self
        def order(*) = self
        def where(created_at:) = tap { @window = created_at }
      end.new([failed, no_error])
      stub_const("SolidQueue::FailedExecution", relation)

      expect(check.failed_executions).to eq([["WeatherUpdateJob", "Weather::TransientError", "Open-Meteo 503", 2.hours.ago],
        ["DailyDigestJob", nil, nil, 1.hour.ago]])
      expect(relation.window).to eq((now - 1.day)..)
    end

    it "doesn't look for them where Solid Queue isn't the queue" do
      expect(check.failed_executions).to eq([])
    end
  end

  describe "weather" do
    it "lists an active cell with days missing or empty in the last week, or an old forecast" do
      current_cell
      cell.weather_days.where(date: [Date.new(2026, 7, 18), Date.new(2026, 7, 19)]).delete_all
      cell.weather_days.where(date: Date.new(2026, 7, 15)).update_all(et0_in: nil)
      cell.weather_forecasts.update_all(issued_at: 26.hours.ago)

      missing = problem(:missing_weather)
      expect(missing.summary).to eq("1 weather cell missing weather")
      expect(missing.details.sole).to eq("Cell #{cell.id} (#{format("%.4f, %.4f", cell.latitude, cell.longitude)}): " \
        "2 days missing in the last 7; 1 day without ET or precipitation; forecast issued 26 h ago")
    end

    it "notes an active cell with no forecast at all" do
      current_cell
      cell.weather_forecasts.delete_all
      expect(problem(:missing_weather).details.sole).to end_with("): no forecast")
    end

    it "clears once the data arrives" do
      current_cell
      cell.weather_days.where(date: Date.new(2026, 7, 19)).delete_all
      expect(problem(:missing_weather)).to be_present
      cell.weather_days.create!(date: Date.new(2026, 7, 19), et0_in: 0.2, precip_in: 0, model: "best_match", hours: 24,
        fetched_at: now)
      expect(problem(:missing_weather)).to be_nil
    end

    it "lists a cell whose fetch failed in the last day, active or not" do
      cell.update!(last_error: "Open-Meteo 503", last_error_at: 3.hours.ago)
      expect(problem(:missing_weather).details.sole).to end_with("fetch failed 3 h ago: Open-Meteo 503")

      cell.update!(last_error_at: 2.days.ago)
      expect(problem(:missing_weather)).to be_nil
    end
  end

  describe "stored runs" do
    it "keeps the last run for the admin page and /up, and counts failed jobs since it" do
      expect(described_class.last).to be_nil
      first = described_class.run(now: now - 1.day)
      expect(described_class.last).to eq(first)

      allow_any_instance_of(described_class).to receive(:failed_executions) do |instance|
        expect(instance.since).to eq(now - 1.day)
        []
      end
      described_class.run(now:)
      expect(described_class.last.checked_at).to eq(now)
    end

    it "is overdue where jobs run once the morning run is missed" do
      allow(described_class).to receive(:solid_queue?).and_return(true)
      allow_any_instance_of(described_class).to receive(:failed_executions).and_return([])
      expect(described_class.overdue?(now:)).to be(true)
      described_class.run(now: now - 25.hours)
      expect(described_class.overdue?(now:)).to be(false)
      expect(described_class.overdue?(now: now + 2.hours)).to be(true)
    end

    it "is never overdue without a job runner (development and test)" do
      expect(described_class.overdue?(now:)).to be(false)
    end
  end
end

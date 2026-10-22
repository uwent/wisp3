require "rails_helper"

RSpec.describe HealthCheck do
  let(:now) { Time.zone.local(2026, 7, 20, 7) }
  let(:check) { described_class.new(now:) }
  let(:field) { create(:field, pivot: create(:pivot, latitude: 44.12, longitude: -89.53)) }
  let(:cell) { field.pivot.reload.weather_cell }

  around { |example| travel_to(now) { example.run } }

  # An active cell with yesterday's weather, fetched and forecast this morning
  def current_cell
    create(:planting, field:, season_start: Date.new(2026, 7, 1), end_date: Date.new(2026, 9, 30))
    cell.update!(timezone: "America/Chicago", last_fetched_at: 2.hours.ago)
    cell.weather_days.create!(date: Date.new(2026, 7, 19), model: "best_match", hours: 24, fetched_at: 2.hours.ago)
    cell.weather_forecasts.create!(issued_at: 2.hours.ago, model: "best_match", payload: {days: []})
    cell
  end

  def problem(kind) = check.problems.find { |problem| problem.kind == kind }

  it "finds nothing wrong when the weather is current, no job failed and every digest went out" do
    current_cell
    create(:user, digest_frequency: "daily", digest_sent_on: Date.new(2026, 7, 20))
    expect(check.problems).to eq([])
  end

  it "groups failed jobs by class, with counts and the latest error's first line" do
    allow(check).to receive(:failed_executions).and_return([
      ["WeatherUpdateJob", "Weather::TransientError", "Open-Meteo 503", 3.days.ago],
      ["WeatherUpdateJob", "Weather::TransientError", "Open-Meteo 502\nretry later", 2.hours.ago],
      ["DailyDigestJob", "RuntimeError", "boom", 1.hour.ago]
    ])
    failed = problem(:failed_jobs)
    expect(failed.summary).to eq("3 failed jobs, 2 new in the last 24 h")
    expect(failed.details.map(&:text)).to eq([
      "WeatherUpdateJob: 2 failed (1 in the last 24 h), latest 2 h ago: Weather::TransientError: Open-Meteo 502",
      "DailyDigestJob: 1 failed (1 in the last 24 h), latest 1 h ago: RuntimeError: boom"
    ])
  end

  it "doesn't look for failed jobs where Solid Queue isn't the queue" do
    expect(check.failed_executions).to eq([])
  end

  it "lists an active cell missing yesterday's weather, not fetched for a day or with an old forecast" do
    current_cell
    cell.weather_days.where(date: Date.new(2026, 7, 19)).delete_all
    cell.weather_days.create!(date: Date.new(2026, 7, 17), model: "best_match", hours: 24, fetched_at: 3.days.ago)
    cell.update!(last_fetched_at: 30.hours.ago)
    cell.weather_forecasts.update_all(issued_at: 26.hours.ago)

    stale = problem(:stale_weather)
    expect(stale.summary).to eq("1 weather cell stale or failing")
    expect(stale.details.sole.text).to eq("Cell #{cell.id} (#{format("%.4f, %.4f", cell.latitude, cell.longitude)}): " \
      "weather stored only through 2026-07-17; last fetched 30 h ago; forecast issued 26 h ago")
  end

  it "lists a cell whose fetch failed in the last day, active or not" do
    cell.update!(last_error: "Open-Meteo 503", last_error_at: 3.hours.ago)
    expect(problem(:stale_weather).details.sole.text).to end_with("fetch failed 3 h ago: Open-Meteo 503")

    cell.update!(last_error_at: 2.days.ago)
    expect(problem(:stale_weather)).to be_nil
  end

  describe "the daily digest" do
    let(:user) { create(:user, digest_frequency: "daily", email: "jane@example.com") }

    before do
      pivot = create(:pivot, farm: create(:farm, group: user.groups.first))
      digest_weather(pivot)
      digest_field(pivot, "North", 12)
    end

    it "lists users it was due for this morning who didn't get it" do
      digest = problem(:digest_not_sent)
      expect(digest.summary).to eq("1 user didn't get today's daily email")
      expect(digest.details.sole).to have_attributes(text: "jane@example.com", user_id: user.id)
    end

    it "lists the first few by email, and how many more" do
      6.times { |n| create(:membership, user: create(:user, digest_frequency: "daily", email: "u#{n}@example.com"), group: user.groups.first) }
      details = problem(:digest_not_sent).details
      expect(details.map(&:text)).to eq(%w[jane@example.com u0@example.com u1@example.com u2@example.com
        u3@example.com] + ["and 2 more"])
    end

    it "leaves out users who got it, or for whom it wasn't due" do
      user.update!(digest_sent_on: Date.new(2026, 7, 20))
      create(:membership, user: create(:user), group: user.groups.first) # the digest is off
      expect(problem(:digest_not_sent)).to be_nil
    end

    it "waits until the digest has run at 6" do
      expect(described_class.new(now: Time.zone.local(2026, 7, 20, 6, 15)).problems.map(&:kind))
        .not_to include(:digest_not_sent)
    end
  end
end

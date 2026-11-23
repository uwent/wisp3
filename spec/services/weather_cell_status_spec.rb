require "rails_helper"

RSpec.describe WeatherCellStatus do
  def add_cell(latitude)
    field = create(:field, system: create(:system, latitude:, longitude: -89.53))
    create(:planting, field:, season_start: Date.new(2026, 7, 10), end_date: Date.new(2026, 9, 30))
    cell = field.system.reload.weather_cell
    (Date.new(2026, 7, 10)..Date.new(2026, 7, 17)).each do |date|
      cell.weather_days.create!(date:, model: "best_match", hours: 24, fetched_at: Time.current)
    end
    cell.weather_forecasts.create!(issued_at: 2.hours.ago, model: "best_match", payload: {days: [{date: "2026-08-04"}]})
    cell.weather_forecasts.create!(issued_at: 1.hour.ago, model: "ens", kind: "ensemble", payload: {members: []})
    cell
  end

  def count_queries(&block)
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
    result = ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    [count, result]
  end

  around { |example| travel_to(Time.zone.parse("2026-07-20 12:00")) { example.run } }

  it "shows the deterministic forecast, not a newer ensemble" do
    cell = add_cell(44.12)
    status = described_class.all.sole
    expect(status.forecast_issued_at).to eq(cell.latest_forecast.issued_at)
    expect(status).to have_attributes(forecast_through: "2026-08-04", season_start: Date.new(2026, 7, 10),
      days_stored: 8, missing_days: 2)
  end

  it "runs the same queries however many cells there are" do
    add_cell(44.12)
    one, = count_queries { described_class.all }
    add_cell(45.5)
    add_cell(46.2)
    three, statuses = count_queries { described_class.all }
    expect(three).to eq(one)
    expect(statuses.map(&:missing_days)).to eq([2, 2, 2])
  end
end

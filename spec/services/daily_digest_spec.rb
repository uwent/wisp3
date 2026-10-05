require "rails_helper"

RSpec.describe DailyDigest do
  let(:user) { create(:user) }
  let(:group) { user.groups.first }
  let(:farm) { create(:farm, group:, name: "Home") }
  let(:pivot) { create(:pivot, farm:, name: "Pivot 1") }

  def field_at(name, moisture_pct) = digest_field(pivot, name, moisture_pct)

  before { digest_weather(pivot) }

  around { |example| travel_to(digest_today) { example.run } }

  it "puts fields needing attention first, soonest first, with their outlook" do
    fine = field_at("Fine", 15)
    soon = field_at("Soon", 12)
    now = field_at("Now", 9)

    digest = described_class.new(user)
    expect(digest.entries.map(&:field)).to eq([now, soon, fine])
    expect(digest.attention.map(&:field)).to eq([now, soon])
    expect(digest.entries.map { |entry| entry.status.status }).to eq(%i[irrigate caution ok])
    expect(digest.entries[1].outlook).to have_attributes(urgent: true, headline: "Irrigate by Wed, Jul 22")
    expect(digest.entries[1].outlook.detail).to match(/\AProjected to reach the irrigation point in 2 days; about 1\.\d\d in would refill/)
    expect(digest.subject).to eq("WISP: 1 field to irrigate, 1 to watch (Mon, Jul 20)")
    expect(digest).to be_deliverable
  end

  it "moves \"Irrigate by\" back for planned irrigation, and forward for heat" do
    field = field_at("North", 12)
    expect(described_class.new(user).entries.sole.outlook.headline).to eq("Irrigate by Wed, Jul 22")

    field.field_entries.create!(date: Date.new(2026, 7, 21), irrigation_in: 1.0)
    expect(described_class.new(user).entries.sole.outlook.headline).to eq("Irrigate by Mon, Jul 27")

    forecast = pivot.weather_cell.weather_forecasts.sole
    forecast.update!(payload: {days: forecast.payload["days"].map { |day| day.merge("et0_in" => 0.35) }})
    expect(described_class.new(user).entries.sole.outlook.headline).to eq("Irrigate by Fri, Jul 24")
  end

  it "moves \"Irrigate by\" back for rain in the forecast" do
    field_at("North", 15)
    expect(described_class.new(user).entries.sole.outlook.headline).to eq("Irrigate by Sat, Jul 25")

    forecast = pivot.weather_cell.weather_forecasts.sole
    forecast.update!(payload: {days: forecast.payload["days"].map { |day| day.merge("precip_in" => (day["date"] == "2026-07-21") ? 1.5 : 0.0) }})
    digest = described_class.new(user)
    expect(digest.entries.sole.outlook.headline).to eq("Irrigate by Mon, Jul 27")
    expect(digest.subject).to eq("WISP: 1 field OK (Mon, Jul 20)")
  end

  it "covers only fields in season, in the user's operations, that they haven't left out" do
    included = field_at("Included", 15)
    left_out = field_at("Left out", 15)
    create(:planting, field: create(:field, pivot:, name: "Last year"), season_start: Date.new(2025, 5, 1),
      emergence_date: Date.new(2025, 5, 1), end_date: Date.new(2025, 9, 1))
    someone_elses = create(:field, pivot: create(:pivot, farm: create(:farm)))
    create(:planting, field: someone_elses, season_start: Date.new(2026, 7, 1), emergence_date: Date.new(2026, 7, 1))

    user.digest_exclusions.create!(subject: left_out)
    expect(described_class.new(user).entries.map(&:field)).to eq([included])
  end

  it "says why it wouldn't send" do
    expect(described_class.new(user).skip_reason).to eq("No included field has a crop in season today.")
    field_at("North", 15)
    user.update!(digest: false)
    expect(described_class.new(user.reload).skip_reason).to eq("The digest is turned off.")
  end

  it "formats depths in the user's units" do
    user.update!(unit_system: "metric")
    expect(described_class.new(user).depth(0.5)).to eq("12.7 mm")
    expect(described_class.new(user).depth(-0.001)).to eq("0.0 mm")
    expect(described_class.new(create(:user)).depth(0.5)).to eq("0.50 in")
  end
end

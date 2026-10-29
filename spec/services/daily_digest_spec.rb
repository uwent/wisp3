require "rails_helper"

RSpec.describe DailyDigest do
  let(:user) { create(:user, digest_frequency: "daily") }
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
    expect(digest.entries[1].outlook.detail).to match(/\AProjected to reach the irrigation point in 2 days, when about 1\.\d\d in would refill/)
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
    expect(described_class.new(user).skip_reason).to eq("No fields are included in your daily email.")
    off = digest_field(pivot, "Off", 15)
    off.plantings.sole.update!(end_date: Date.new(2026, 7, 10))
    expect(described_class.new(user).skip_reason).to eq("No included field has a crop in season today.")
    # Daily all year sends anyway, with the weather
    user.update!(digest_frequency: "daily_all_year")
    digest = described_class.new(user)
    expect(digest).to be_deliverable
    expect(digest.subject).to eq("WISP: no crops in season (Mon, Jul 20)")
    expect(digest.operations.sole.farms.sole.zones.sole.pivots.sole).to have_attributes(pivot:, entries: [])

    user.update!(digest_frequency: "daily")
    field_at("North", 15)
    user.update!(digest_frequency: "never")
    expect(described_class.new(user.reload).skip_reason).to eq("The daily email is turned off.")
    user.update!(digest_frequency: "daily", confirmed_at: nil)
    expect(described_class.new(user.reload).skip_reason).to eq("The email address isn't confirmed.")
  end

  it "only sends on days a field needs water, for those who asked for that" do
    field = field_at("North", 15)
    user.update!(digest_frequency: "needed")
    expect(described_class.new(user).skip_reason).to eq("No field needs irrigation in the next 3 days.")

    field.field_entries.find_by!(date: Date.new(2026, 7, 19)).update!(soil_moisture_pct: 12)
    expect(described_class.new(user)).to be_deliverable
  end

  it "groups fields by operation, farm, weather zone and pivot, in name order, with each zone's weather" do
    other_pivot = create(:pivot, farm:, name: "Pivot 0", weather_cell: pivot.weather_cell)
    river = create(:farm, group:, name: "River")
    river_pivot = create(:pivot, farm: river, name: "East", weather_cell: pivot.weather_cell)
    b = field_at("B", 15)
    a = field_at("A", 9)
    zero = digest_field(other_pivot, "Zero", 15)
    east = digest_field(river_pivot, "East 1", 12)

    elsewhere = create(:pivot, farm: river, name: "West", latitude: 45.5, longitude: -91.5)
    digest_weather(elsewhere)
    west = digest_field(elsewhere, "West 1", 15)

    digest = described_class.new(user)
    farms = digest.operations.sole.farms
    expect(farms.map { |section| [section.farm.name, section.zones.map { |zone| [zone.number, zone.cell, zone.pivots.map { |p| [p.pivot.name, p.entries.map(&:field)] }] }] })
      .to eq([["Home", [[1, pivot.weather_cell, [["Pivot 0", [zero]], ["Pivot 1", [a, b]]]]]],
        ["River", [[1, pivot.weather_cell, [["East", [east]]]], [2, elsewhere.weather_cell, [["West", [west]]]]]]])
    expect(farms.first.zones.first.weather[:past]).to have_attributes(days: 7, precip: 0.0, tmax: 85.0..85.0)
    expect(farms.first.zones.first.weather[:ahead]).to have_attributes(days: 7, tmin: 62..62)
    # One operation: its heading gives way to a line at the top; two farms keep theirs
    expect(digest).to have_attributes(several_groups?: false, several_farms?: true, context: [["Operation", group.name]])
  end

  it "lists the included fields the user chose: all, in season, needing action, or needing irrigation" do
    soon = field_at("Soon", 12) # caution, and a moisture reading yesterday
    stale = field_at("Stale", 15)
    stale.plantings.sole.canopy_observations.update_all(pct_cover: 40) # on Jul 1: a cover reading is due
    fine = field_at("Fine", 15)
    off = field_at("Off", 15)
    off.plantings.sole.update!(end_date: Date.new(2026, 7, 10))

    listed = ->(scope) { user.update!(digest_scope: scope) && described_class.new(user.reload).listed.map(&:field) }
    expect(listed.call("all")).to contain_exactly(soon, stale, fine, off)
    expect(listed.call("in_season")).to contain_exactly(soon, stale, fine)
    expect(listed.call("needs_action")).to contain_exactly(soon, stale)
    expect(listed.call("needs_irrigation")).to eq([soon])

    digest = described_class.new(user)
    expect(digest.counts).to have_attributes(fields: 1, pivots: 1, covered_fields: 4, covered_pivots: 1, planted: 4)
    expect(digest.context).to eq([["Operation", group.name], ["Farm", "Home"]])
  end

  it "says when nothing needs doing, and still shows the in-season pivots' weather" do
    field = field_at("Fine", 15) # its readings are up to date, and the canopy closed
    user.update!(digest_scope: "needs_irrigation")
    digest = described_class.new(user)
    expect(digest.nothing_listed).to eq("No field needs irrigation now or within 3 days.")
    expect(digest.operations.sole.farms.sole.zones.sole.pivots.sole.entries).to eq([])

    user.update!(digest_scope: "needs_action")
    expect(described_class.new(user).nothing_listed).to eq("No field needs irrigation or a reading today.")

    field.plantings.sole.update!(end_date: Date.new(2026, 7, 10))
    user.update!(digest_scope: "in_season", digest_frequency: "daily_all_year")
    expect(described_class.new(user).nothing_listed).to eq("No included field has a crop in season today.")
  end

  it "formats depths in the user's units" do
    user.update!(unit_system: "metric")
    expect(described_class.new(user).depth(0.5)).to eq("12.7 mm")
    expect(described_class.new(user).depth(-0.001)).to eq("0.0 mm")
    expect(described_class.new(create(:user)).depth(0.5)).to eq("0.50 in")
  end

  it "formats temperature ranges in the user's units" do
    expect(described_class.new(user).temperatures(68.4..82.0)).to eq("68–82°F")
    expect(described_class.new(user).temperatures(75.0..75.2)).to eq("75°F")
    user.update!(unit_system: "metric")
    expect(described_class.new(user).temperatures(32.0..82.0)).to eq("0–28°C")
  end
end

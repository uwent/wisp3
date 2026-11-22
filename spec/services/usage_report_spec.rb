require "rails_helper"

RSpec.describe UsageReport do
  let(:today) { Date.new(2026, 7, 20) }
  let(:report) { travel_to(today.in_time_zone.change(hour: 12)) { described_class.new(2026, today:).props } }

  def grower(email, signed_up: Time.zone.local(2026, 4, 1), confirmed: true, **attributes)
    create(:user, email:, created_at: signed_up, confirmed_at: confirmed ? signed_up : nil, **attributes)
  end

  def operation_for(user, planting: true)
    group = create(:group)
    create(:membership, user:, group:, owner: true)
    field = create(:field, pivot: create(:pivot, farm: create(:farm, group:), kind: "center"))
    create(:planting, field:) if planting
    field
  end

  def active(user, *dates, areas: %w[dashboard], phone: false)
    dates.each { |date| ActivityDay.create!(user:, date:, areas:, phone:) }
  end

  it "follows the season's sign-ups through the funnel, each step counting only those past the one before" do
    regular = grower("regular@farm.test")
    field = operation_for(regular)
    travel_to(Time.zone.local(2026, 6, 2, 9)) { create(:field_entry, field:, rain_in: 0.4) }
    active(regular, *(Date.new(2026, 6, 1)..Date.new(2026, 6, 10)))

    planted = grower("planted@farm.test")
    operation_for(planted)
    farm_only = grower("farm@farm.test")
    operation_for(farm_only).pivot.plantings.destroy_all
    grower("unconfirmed@farm.test", confirmed: false)
    # Active often but never set anything up: not a regular in the funnel
    idle = grower("idle@farm.test")
    active(idle, *(Date.new(2026, 6, 1)..Date.new(2026, 6, 12)))
    grower("last-year@farm.test", signed_up: Time.zone.local(2025, 5, 1))

    expect(report[:funnel].to_h { |step| [step[:key].to_sym, step[:count]] })
      .to eq(signed_up: 5, confirmed: 4, farm: 3, planting: 2, entry: 1, regular: 1)
  end

  it "leaves out admins, the demo account and the example farm" do
    admin = grower("staff@farm.test", admin: true)
    demo = grower("demo@example.com")
    operation_for(demo)
    example = create(:group, example_as_of: Date.new(2026, 7, 20))
    create(:farm, group: example)
    active(admin, today)
    active(demo, today)

    expect(report[:tiles]).to include(accounts: 0, new_accounts: 0, active_week: 0)
    expect(report[:setup]).to include(operations: 0, farms: 0, plantings: 0)
    expect(report[:funnel].first[:count]).to eq(0)
  end

  it "counts accounts active each week, by part of WISP, on phones, and coming back from last season" do
    a = grower("a@farm.test", signed_up: Time.zone.local(2025, 4, 1))
    b = grower("b@farm.test")
    active(a, Date.new(2025, 6, 3))
    active(a, Date.new(2026, 7, 14), Date.new(2026, 7, 15), areas: %w[dashboard map], phone: true)
    active(b, Date.new(2026, 7, 16), areas: %w[daily])
    active(b, Date.new(2026, 5, 1), areas: %w[setup])

    weeks = report[:weeks]
    expect(weeks.first).to eq("2026-02-23")
    expect(weeks.last).to eq("2026-11-30")
    expect(report[:weekly_active][weeks.index("2026-07-13")]).to eq(2)
    expect(report[:weekly_active].sum).to eq(3)
    # 2025's week of June 2 lines up with 2026's of June 1
    expect(report[:previous_weekly_active][weeks.index("2026-06-01")]).to eq(1)
    expect(report[:tiles]).to include(active_week: 2, active_month: 2)
    expect(report[:areas][:month_active]).to eq(2)
    expect(report[:areas][:counts]).to include({area: "dashboard", season: 1, month: 1},
      {area: "setup", season: 1, month: 0}, {area: "daily", season: 1, month: 1})
    expect(report[:phone_share]).to eq(0.5)
    expect(report[:return_rate]).to eq(previous_year: 2025, active: 1, returned: 1)
  end

  it "counts entries by the week they were made, by kind" do
    user = grower("a@farm.test")
    field = operation_for(user)
    planting = field.plantings.sole
    travel_to(Time.zone.local(2026, 7, 14, 9)) do
      create(:field_entry, field:, date: Date.new(2026, 7, 13), rain_in: 0.5, irrigation_in: 0.75, soil_moisture_pct: 30)
      plot = create(:planting, field: create(:field, pivot: field.pivot), partial: true, area_acres: 1)
      plot.planting_entries.create!(date: Date.new(2026, 7, 14), irrigation_in: 0.5)
      create(:canopy_observation, planting:, date: Date.new(2026, 7, 14))
    end
    # Entered after the season's weeks: counted for operations entering data, not on the chart
    travel_to(Time.zone.local(2026, 12, 20, 9)) { create(:field_entry, field:, date: Date.new(2026, 12, 19), rain_in: 0.1) }

    week = report[:weeks].index("2026-07-13")
    expect(report[:weekly_entries].transform_values { |counts| counts[week] })
      .to eq(rain: 1, irrigation: 2, soil_moisture: 1, canopy: 1)
    expect(report[:weekly_entries][:rain].sum).to eq(1)
    expect(report[:tiles][:operations_entering]).to eq(1)
  end

  it "describes how operations are set up" do
    a = grower("a@farm.test", unit_system: "metric", digest_frequency: "daily")
    b = grower("b@farm.test")
    field = operation_for(a)
    create(:membership, user: b, group: field.pivot.farm.group)
    field.update!(boundary: {type: "Polygon", coordinates: [[[-89.53, 44.12], [-89.52, 44.12], [-89.52, 44.13], [-89.53, 44.12]]]})

    expect(report[:setup]).to include(operations: 1, shared_operations: 1, farms: 1, fields: 1, outlined_fields: 1,
      plantings: 1, plots: 0, systems: [{name: "Pivot", count: 1}], units: {"metric" => 1, "imperial" => 1},
      digests: {"daily" => 1, "never" => 1})
    expect(report[:setup][:crops].sole[:count]).to eq(1)
    expect(report[:return_rate]).to be_nil
    expect(report[:previous_weekly_active]).to be_nil
  end
end

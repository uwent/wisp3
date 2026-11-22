require "rails_helper"

RSpec.describe DailyEntryWeek do
  let(:group) { create(:group) }
  let(:farm) { create(:farm, group:, name: "Home") }
  let(:east) { create(:pivot_group, farm:, name: "East") }
  let(:north) { create(:pivot, farm:, pivot_group: east, name: "North") }
  let(:south) { create(:pivot, farm:, pivot_group: east, name: "South", pump_capacity_gpm: 800) }
  let(:lane) { create(:pivot, farm:, name: "Lane 3") }
  let(:idle) { create(:pivot, farm:, name: "Idle") }
  let(:date) { Date.new(2026, 7, 20) }
  let(:week) { (Date.new(2026, 7, 14)..date).to_a }

  around { |example| travel_to(date) { example.run } }

  def field_on(pivot, name, from: Date.new(2026, 4, 20), to: Date.new(2026, 9, 30))
    field = create(:field, pivot:, name:)
    create(:planting, field:, season_start: from, emergence_date: from + 10, end_date: to) if from
    field
  end

  def props = described_class.new(group, date).props

  def farm_props = props[:farms].sole

  it "lists rain by irrigation group, then systems in no group, and irrigation by system in season" do
    field_on(north, "N1")
    field_on(south, "S1")
    field_on(lane, "L1")
    field_on(idle, "Fallow", from: nil)

    expect(props).to include(date:, start: week.first, dates: week)
    expect(farm_props[:rain_rows].map { |row| row.values_at(:key, :name, :kind) })
      .to eq([["group-#{east.id}", "East", "group"], ["pivot-#{lane.id}", "Lane 3", "system"]])
    expect(farm_props[:rain_rows].first[:systems]).to eq(2)
    expect(farm_props[:irrigation_rows].map { |row| row[:name] }).to eq(["North", "South", "Lane 3"])
    expect(farm_props[:irrigation_rows].map { |row| row[:hours] }).to eq([false, true, false])
  end

  it "leaves out a farm with nothing in season" do
    field_on(idle, "Fallow", from: nil)
    expect(props[:farms]).to be_empty
  end

  it "marks the days each row takes a value: a field in season under it" do
    field_on(lane, "L1", from: Date.new(2026, 7, 17))
    row = farm_props[:rain_rows].sole
    expect(row[:days].map { |day| day[:active] }).to eq([false, false, false, true, true, true, true])
    expect(farm_props[:irrigation_rows].sole[:days].map { |day| day[:active] })
      .to eq([false, false, false, true, true, true, true])
  end

  it "gives a group's rain as its fields' common value, or varies, with each field's amount" do
    n1 = field_on(north, "N1")
    s1 = field_on(south, "S1")
    n1.field_entries.create!(date: week[1], rain_in: 0.4)
    s1.field_entries.create!(date: week[1], rain_in: 0.4, irrigation_in: 0.5)
    n1.field_entries.create!(date: week[3], rain_in: 0.4)
    s1.field_entries.create!(date: week[3], rain_in: 0.6)

    days = farm_props[:rain_rows].sole[:days]
    expect(days[0]).to include(active: true, value: nil, varies: false)
    expect(days[1]).to include(value: 0.4, varies: false)
    expect(days[3]).to include(value: nil, varies: true,
      fields: [{id: n1.id, name: "N1", rain_in: 0.4}, {id: s1.id, name: "S1", rain_in: 0.6}])
  end

  it "gives each day's irrigation, naming the fields when it applies to only some" do
    n1 = field_on(north, "N1")
    field_on(north, "N2")
    create(:pivot_irrigation, pivot: north, date: week[0], inches: 0.8)
    create(:pivot_irrigation, pivot: north, date: week[2], inches: 0.6, field_ids: [n1.id])

    days = farm_props[:irrigation_rows].sole[:days]
    expect(days[0]).to include(irrigation: {"inches" => 0.8, "run_hours" => nil, "percent_timer" => nil, "circles" => nil,
                                            "field_ids" => nil}, some_fields: nil)
    expect(days[1]).to include(irrigation: nil, some_fields: nil)
    expect(days[2]).to include(irrigation: include("field_ids" => [n1.id]), some_fields: ["N1"])
  end

  it "places a field that moved systems mid-week under the system its season ran on each day" do
    moved = field_on(north, "Moved", to: Date.new(2026, 7, 16))
    moved.update!(pivot: lane)
    create(:planting, field: moved, season_start: Date.new(2026, 7, 17), emergence_date: Date.new(2026, 7, 20),
      end_date: Date.new(2026, 9, 30))

    rows = farm_props[:rain_rows].to_h { |row| [row[:name], row[:days].map { |day| day[:fields].map { |f| f[:name] } }] }
    expect(rows["East"]).to eq([["Moved"]] * 3 + [[]] * 4)
    expect(rows["Lane 3"]).to eq([[]] * 3 + [["Moved"]] * 4)
    irrigation = farm_props[:irrigation_rows].to_h { |row| [row[:name], row[:days].map { |day| day[:active] }] }
    expect(irrigation).to eq("North" => [true] * 3 + [false] * 4, "Lane 3" => [false] * 3 + [true] * 4)
  end

  it "loads the week in a few queries, however many fields and days" do
    create(:pivot_irrigation, pivot: north, date: week[2])
    count_for = ->(fields) {
      fields.times { |n| field_on([north, south, lane][n % 3], "F#{fields}-#{n}").field_entries.create!(date: week[n % 7], rain_in: 0.1) }
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { described_class.new(group, date).props }
      count
    }
    few = count_for.call(3)
    expect(count_for.call(9)).to eq(few)
    expect(few).to be <= 10
  end
end

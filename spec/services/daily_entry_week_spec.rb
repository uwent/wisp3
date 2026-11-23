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
    expect(farm_props[:irrigation_rows].map { |row| row.values_at(:key, :name, :id, :kind, :kind_name) })
      .to eq([["pivot-#{north.id}", "North", north.id, "center", "Pivot"], ["pivot-#{south.id}", "South", south.id, "center", "Pivot"],
        ["pivot-#{lane.id}", "Lane 3", lane.id, "center", "Pivot"]])
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
      fields: [{id: n1.id, name: "N1", value: 0.4}, {id: s1.id, name: "S1", value: 0.6}])
  end

  it "gives each day's irrigation as its fields' common value, or varies, with each field's amount" do
    n1 = field_on(north, "N1")
    n2 = field_on(north, "N2")
    n1.field_entries.create!(date: week[0], irrigation_in: 0.8)
    n2.field_entries.create!(date: week[0], irrigation_in: 0.8, rain_in: 0.1)
    n1.field_entries.create!(date: week[2], irrigation_in: 0.6)
    n2.field_entries.create!(date: week[3], rain_in: 0.3)

    days = farm_props[:irrigation_rows].sole[:days]
    expect(days[0]).to eq(active: true, value: 0.8, varies: false,
      fields: [{id: n1.id, name: "N1", value: 0.8, acres: 60.0}, {id: n2.id, name: "N2", value: 0.8, acres: 60.0}])
    expect(days[1]).to include(value: nil, varies: false)
    expect(days[2]).to include(varies: true,
      fields: [{id: n1.id, name: "N1", value: 0.6, acres: 60.0}, {id: n2.id, name: "N2", value: nil, acres: 60.0}])
    expect(days[3]).to include(value: nil, varies: false)
  end

  it "leaves a rainfed field or plot out of a system's irrigation, which it doesn't fill (D17)" do
    n1 = field_on(north, "N1")
    dry = field_on(north, "Dry")
    dry.plantings.sole.update!(rainfed: true)
    dry.field_entries.create!(date: week[0], irrigation_in: 0.3)
    n1.field_entries.create!(date: week[0], irrigation_in: 0.8)
    expect(farm_props[:irrigation_rows].sole[:days][0]).to include(active: true, value: 0.8, varies: false,
      fields: [{id: n1.id, name: "N1", value: 0.8, acres: 60.0}])

    lone = field_on(lane, "Lone")
    lone.plantings.sole.update!(rainfed: true)
    # A system with only rainfed fields has no irrigation row, but its rain
    expect(farm_props[:irrigation_rows].map { |row| row[:name] }).to eq(["North"])
    expect(farm_props[:rain_rows].find { |row| row[:name] == "Lane 3" }[:days][0]).to include(active: true)
  end

  it "gives no common value on a day some fields have an amount and others none" do
    n1 = field_on(north, "N1")
    field_on(north, "N2")
    n1.field_entries.create!(date: week[2], irrigation_in: 0.6)
    expect(farm_props[:irrigation_rows].sole[:days][2]).to include(value: nil, varies: true)
  end

  it "gives a field growing only plots as its plots, for irrigation (as the day page does), and as itself for rain" do
    plots = create(:field, pivot: north, name: "Plots")
    season = {season_start: Date.new(2026, 4, 20), emergence_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 9, 30)}
    corn = create(:planting, field: plots, partial: true, area_acres: 1, plant: create(:plant, name: "Corn"), **season)
    beans = create(:planting, field: plots, partial: true, area_acres: 2, plant: create(:plant, name: "Beans"), **season)
    corn.planting_entries.create!(date: week[0], irrigation_in: 0.5)
    beans.planting_entries.create!(date: week[0], irrigation_in: 0.5)

    day = farm_props[:irrigation_rows].sole[:days][0]
    expect(day).to include(value: 0.5, varies: false)
    expect(day[:fields]).to contain_exactly(
      {id: corn.id, name: "Plots: Corn", value: 0.5, acres: 1.0, plot: true},
      {id: beans.id, name: "Plots: Beans", value: 0.5, acres: 2.0, plot: true}
    )
    expect(farm_props[:rain_rows].sole[:days][0][:fields]).to eq([{id: plots.id, name: "Plots", value: nil}])
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
    count_for = ->(fields) {
      fields.times do |n|
        field_on([north, south, lane][n % 3], "F#{fields}-#{n}").field_entries.create!(date: week[n % 7], rain_in: 0.1, irrigation_in: 0.5)
      end
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

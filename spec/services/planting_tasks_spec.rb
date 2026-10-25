require "rails_helper"

RSpec.describe PlantingTasks do
  let(:pivot) { create(:pivot) }
  let(:field) { create(:field, pivot:) }
  let(:planting) do
    create(:planting, field:, season_start: Date.new(2026, 7, 1), emergence_date: Date.new(2026, 7, 1),
      end_date: Date.new(2026, 9, 30))
  end

  before { digest_weather(pivot) }

  around { |example| travel_to(digest_today) { example.run } }

  def tasks = PlantingStatus.new(planting.reload).tasks

  it "asks for soil moisture and percent cover weekly, from none yet" do
    expect(tasks.map { |task| [task.kind, task.due, task.todo] }).to eq([
      [:soil_moisture, true, "Enter a soil moisture reading (none yet this season)"],
      [:canopy, true, "Enter a percent cover reading (none yet this season)"]
    ])

    field.field_entries.create!(date: Date.new(2026, 7, 15), soil_moisture_pct: 10)
    create(:canopy_observation, planting:, date: Date.new(2026, 7, 8), pct_cover: 40)
    moisture, cover = tasks
    expect(moisture).to have_attributes(due: false, last_date: Date.new(2026, 7, 15), note: nil, todo: nil)
    expect(cover).to have_attributes(due: true, last_date: Date.new(2026, 7, 8), note: "due",
      todo: "Enter a percent cover reading (last Jul 8)")
  end

  it "stops asking for percent cover once the canopy is nearly closed" do
    create(:canopy_observation, planting:, date: Date.new(2026, 7, 1), pct_cover: 85)
    expect(tasks.find { |task| task.kind == :canopy }).to have_attributes(due: false, note: "canopy closed")
  end

  it "asks for canopy readings only from emergence" do
    planting.update!(emergence_date: Date.new(2026, 7, 25))
    expect(tasks.map(&:kind)).to eq([:soil_moisture])
  end

  it "asks for LAI only once the grower has started entering it" do
    planting.update!(plant: create(:plant, canopy_model: "field_corn"), et_method: "lai")
    expect(tasks.map(&:kind)).to eq([:soil_moisture])
    create(:canopy_observation, planting:, date: Date.new(2026, 7, 10), pct_cover: nil, lai: 2.0)
    expect(tasks.last).to have_attributes(kind: :canopy, label: "Leaf area index (LAI)", due: true)
  end

  it "adds a check when canopy readings run ahead of the crop's curve" do
    planting.update!(plant: create(:plant, key: "potato", name: "Potato"))
    curve = CanopyCurve.for("potato")
    [10, 16].each do |day|
      date = planting.emergence_date + day
      create(:canopy_observation, planting:, date:, pct_cover: curve.cover(planting.emergence_date, date + 9).round)
    end
    check = tasks.last
    expect(check).to have_attributes(kind: :canopy_check, due: true,
      todo: "Check your canopy readings: they're about 9 days ahead of the typical potato curve")
    expect(check.message).to include("check the emergence date (Jul 1)", "WISP still follows the typical curve")
  end

  it "adds a check when a reading falls while the curve grows" do
    planting.update!(plant: create(:plant, key: "potato", name: "Potato"), canopy_interpolation: "linear")
    create(:canopy_observation, planting:, date: Date.new(2026, 7, 12), pct_cover: 30)
    create(:canopy_observation, planting:, date: Date.new(2026, 7, 18), pct_cover: 22.5)
    check = tasks.last
    expect(check.todo).to eq("Check your Jul 18 canopy reading, which is lower than the one before")
    expect(check.message).to include("(22.5%) is lower than the one before it (30%)")
    expect(check.message).not_to include("WISP still follows the typical curve")
  end

  it "has nothing to do outside the season" do
    planting.update!(season_start: Date.new(2026, 8, 1), emergence_date: Date.new(2026, 8, 1))
    expect(tasks).to eq([])
  end
end

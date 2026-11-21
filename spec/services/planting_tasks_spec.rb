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
    moisture, cover = tasks.reject { |task| task.kind == :irrigation_check }
    expect(moisture).to have_attributes(due: false, last_date: Date.new(2026, 7, 15), note: nil, todo: nil)
    expect(cover).to have_attributes(due: true, last_date: Date.new(2026, 7, 8), note: "due",
      todo: "Enter a percent cover reading (last Jul 8)")
  end

  describe "the irrigation check" do
    def check = tasks.find { |task| task.kind == :irrigation_check }

    # A reading below the irrigation point (10% here) puts the balance there from its date
    def dry_from(date) = field.field_entries.create!(date:, soil_moisture_pct: 9.5)

    it "asks after two days in a row at or below the irrigation point with no irrigation entered" do
      dry_from(Date.new(2026, 7, 19))
      expect(tasks.first).to have_attributes(kind: :irrigation_check, label: "Irrigation", due: true,
        date: Date.new(2026, 7, 19), todo: "Irrigated since Sun, Jul 19? Enter it so the balance catches up.")
    end

    it "doesn't ask after one day" do
      dry_from(Date.new(2026, 7, 20))
      expect(PlantingStatus.new(planting.reload).status).to eq(:irrigate)
      expect(check).to be_nil
    end

    it "doesn't ask when irrigation was entered on one of the days, for the field or by its system" do
      dry_from(Date.new(2026, 7, 18))
      expect(check).to have_attributes(date: Date.new(2026, 7, 18))

      entry = field.field_entries.create!(date: Date.new(2026, 7, 19), irrigation_in: 0.05)
      expect(check).to be_nil

      entry.destroy!
      create(:pivot_irrigation, pivot:, date: Date.new(2026, 7, 19), inches: 0.05)
      expect(check).to be_nil
    end

    it "doesn't ask once the season has ended, or time travelling" do
      dry_from(Date.new(2026, 7, 15))
      expect(PlantingStatus.new(planting.reload, as_of: Date.new(2026, 7, 18)).tasks.map(&:kind))
        .not_to include(:irrigation_check)

      planting.update!(end_date: Date.new(2026, 7, 19))
      expect(tasks.map(&:kind)).not_to include(:irrigation_check)
    end
  end

  it "stops asking for percent cover once the canopy is nearly closed" do
    create(:canopy_observation, planting:, date: Date.new(2026, 7, 1), pct_cover: 85)
    expect(tasks.find { |task| task.kind == :canopy }).to have_attributes(due: false, note: "canopy closed")
  end

  it "asks again after a cutting, counting only readings since it" do
    planting.update!(plant: create(:plant, key: "alfalfa", name: "Alfalfa"))
    create(:canopy_observation, planting:, date: Date.new(2026, 7, 6), pct_cover: 85)
    expect(tasks.find { |task| task.kind == :canopy }).to have_attributes(note: "canopy closed")

    planting.canopy_cuttings.create!(date: Date.new(2026, 7, 10))
    expect(tasks.find { |task| task.kind == :canopy })
      .to have_attributes(due: true, last_date: nil, todo: "Enter a percent cover reading (none since the Jul 10 cutting)")

    # A reading on the cutting's date belongs to the regrowth
    create(:canopy_observation, planting:, date: Date.new(2026, 7, 10), pct_cover: 5)
    expect(tasks.find { |task| task.kind == :canopy }).to have_attributes(due: true, last_date: Date.new(2026, 7, 10))
  end

  it "counts no cuttings for a crop that isn't cut, as its balance doesn't (Canopy.for)" do
    planting.update!(plant: create(:plant, key: "alfalfa", name: "Alfalfa"))
    create(:canopy_observation, planting:, date: Date.new(2026, 7, 6), pct_cover: 85)
    planting.canopy_cuttings.create!(date: Date.new(2026, 7, 10))
    planting.update!(plant: create(:plant, key: "potato", name: "Potato"))
    expect(tasks.find { |task| task.kind == :canopy }).to have_attributes(note: "canopy closed")
  end

  it "answers for any date, without a balance" do
    create(:canopy_observation, planting:, date: Date.new(2026, 7, 8), pct_cover: 40)
    expect(described_class.canopy(planting, Date.new(2026, 6, 30))).to be_nil
    expect(described_class.canopy(planting, Date.new(2026, 7, 12))).to have_attributes(due: false, last_date: Date.new(2026, 7, 8))
    expect(described_class.canopy(planting, Date.new(2026, 7, 16))).to have_attributes(due: true)
  end

  it "stops asking for percent cover at vine kill, but not soil moisture" do
    planting.update!(plant: create(:plant, key: "potato", name: "Potato"), vine_kill_date: Date.new(2026, 7, 18))
    expect(tasks.map { |task| [task.kind, task.due, task.note] }).to eq([
      [:soil_moisture, true, "due"], [:canopy, false, "vines killed"]
    ])
  end

  it "asks for canopy readings only from emergence" do
    planting.update!(emergence_date: Date.new(2026, 7, 25))
    expect(tasks.map(&:kind)).to eq([:soil_moisture])
  end

  it "asks for LAI only once the grower has started entering it, listing it as optional until then" do
    planting.update!(plant: create(:plant, canopy_model: "field_corn"), et_method: "lai")
    expect(tasks.last).to have_attributes(kind: :canopy, label: "Leaf area index (LAI)", due: false, note: "optional",
      last_date: nil)
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

  it "says so when canopy readings run behind the curve" do
    planting.update!(plant: create(:plant, key: "potato", name: "Potato"))
    curve = CanopyCurve.for("potato")
    [25, 31].each do |day|
      date = planting.emergence_date + day
      create(:canopy_observation, planting:, date:, pct_cover: curve.cover(planting.emergence_date, date - 10).round)
    end
    check = tasks.last
    expect(check.todo).to eq("Check your canopy readings: they're about 10 days behind the typical potato curve")
    expect(check.message).to include("If your crop isn't growing that much slower")
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

  it "has nothing to do before the season" do
    planting.update!(season_start: Date.new(2026, 8, 1), emergence_date: Date.new(2026, 8, 1))
    expect(tasks).to eq([])
  end

  it "lists the readings with their last dates once the season has ended, none due (G.6)" do
    planting.update!(end_date: Date.new(2026, 7, 15))
    create(:canopy_observation, planting:, date: Date.new(2026, 7, 5), pct_cover: 85)
    expect(tasks.map { |task| [task.kind, task.due, task.note, task.todo, task.last_date] }).to eq([
      [:soil_moisture, false, nil, nil, nil], [:canopy, false, "canopy closed", nil, Date.new(2026, 7, 5)]
    ])
  end
end

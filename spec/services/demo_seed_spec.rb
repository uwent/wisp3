require "rails_helper"

RSpec.describe DemoSeed do
  before { ReferenceData.load! }

  it "builds a demo account with both ET methods, pivot and field irrigation, an irrigation group, a traveler and drip" do
    result = described_class.new(email: "demo@example.com", year: 2026).run
    expect(result).to include(farms: 4, fields: 19, plantings: 25)
    expect(result[:password]).to be_present

    group = User.find_by!(email: "demo@example.com").groups.find_by!(name: DemoSeed::GROUP_NAME)
    expect(group.plantings.pluck(:et_method).uniq).to contain_exactly("pct_cover", "lai")
    expect(group.pivots.map { |pivot| pivot.fields.size }.max).to eq(8)
    expect(PivotIrrigation.where(pivot: group.pivots).where.not(run_hours: nil)).to exist
    expect(group.fields.find_by!(name: "Cabbage").field_entries.where.not(rain_in: nil).count).to eq(5)
    expect(group.plantings.where.not(vine_kill_date: nil).map { |planting| planting.plant.key }).to eq(["potato"])
    research = group.fields.find_by!(name: "Arlington 525")
    expect(research.plantings_on(Date.new(2026, 7, 1)).map(&:partial?)).to eq([true] * 4)
    expect(research.plantings.sum(&:area_acres)).to be < research.area_acres
    expect(PlantingEntry.joins(:planting).where(plantings: {field_id: research.id})).to exist
    expect(group.fields.find_by!(name: "Market garden").plantings.size).to eq(3)
    expect(group.plantings.joins(:plant).find_by!(plants: {key: "alfalfa"}).canopy_cuttings.size).to eq(3)
    expect(group.pivot_groups.sole.pivots.map(&:name)).to eq(["Hay pivot", "River pivot"])
    travelers = group.pivots.where(kind: "traveler")
    expect(travelers.map { |pivot| [pivot.name, pivot.equipment, pivot.fields.size] })
      .to contain_exactly(["West lane", "Hard hose reel #2", 1], ["East lane", "Hard hose reel #2", 1])
    drip = group.pivots.find_by!(kind: "drip")
    expect(drip.pivot_irrigations.first.applied_inches).to be_within(0.01).of(0.18)

    # Some fields have outlines near their acres, and the research field's plots are pinned in it (G.10)
    outlined = group.fields.where.not(boundary: nil)
    expect(outlined.map(&:name)).to contain_exactly("North potatoes", "North corn", "Hay north", "Tomatoes",
      "Arlington 525", "West 20", "East 15")
    expect(group.fields.find_by!(name: "West 20").boundary_acres).to be_within(0.5).of(20)
    expect(research.boundary_acres).to be_within(0.1).of(2)
    research.plantings.each do |plot|
      expect(FieldBoundary.errors(research.boundary)).to be_empty
      inside = plot.longitude.between?(*research.boundary["coordinates"][0].map(&:first).minmax) &&
        plot.latitude.between?(*research.boundary["coordinates"][0].map(&:last).minmax)
      expect(inside).to be(true)
    end
  end

  it "rebuilds rather than duplicating, and keeps the user's password" do
    described_class.new(email: "demo@example.com", password: "a fine password").run
    result = described_class.new(email: "demo@example.com").run
    user = User.find_by!(email: "demo@example.com")
    expect(user.groups.where(name: DemoSeed::GROUP_NAME).count).to eq(1)
    expect(result[:password]).to be_nil
    expect(user.valid_password?("a fine password")).to be(true)
  end
end

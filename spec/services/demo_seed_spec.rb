require "rails_helper"

RSpec.describe DemoSeed do
  before { ReferenceData.load! }

  it "builds a demo account with both ET methods, pivot and field irrigation, and a field group" do
    result = described_class.new(email: "demo@example.com", year: 2026).run
    expect(result).to include(farms: 4, fields: 16, plantings: 22)
    expect(result[:password]).to be_present

    group = User.find_by!(email: "demo@example.com").groups.find_by!(name: DemoSeed::GROUP_NAME)
    expect(group.plantings.pluck(:et_method).uniq).to contain_exactly("pct_cover", "lai")
    expect(group.pivots.map { |pivot| pivot.fields.size }.max).to eq(8)
    expect(PivotIrrigation.where(pivot: group.pivots).where.not(run_hours: nil)).to exist
    expect(group.field_groups.sole.fields.size).to eq(2)
    expect(group.plantings.where.not(vine_kill_date: nil).map { |planting| planting.plant.key }).to eq(["potato"])
    research = group.fields.find_by!(name: "Arlington 525")
    expect(research.plantings_on(Date.new(2026, 7, 1)).map(&:partial?)).to eq([true] * 4)
    expect(research.plantings.sum(&:area_acres)).to be < research.area_acres
    expect(PlantingEntry.joins(:planting).where(plantings: {field_id: research.id})).to exist
    expect(group.fields.find_by!(name: "Market garden").plantings.size).to eq(3)
    expect(group.plantings.joins(:plant).find_by!(plants: {key: "alfalfa"}).canopy_cuttings.size).to eq(3)
    expect(group.pivot_groups.sole.pivots.map(&:name)).to eq(["Hay pivot", "River pivot"])
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

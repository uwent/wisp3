require "rails_helper"

RSpec.describe DemoSeed do
  before { ReferenceData.load! }

  it "builds a demo account with both ET methods, pivot and field irrigation, and a field group" do
    result = described_class.new(email: "demo@example.com", year: 2026).run
    expect(result).to include(farms: 3, fields: 13, plantings: 14)
    expect(result[:password]).to be_present

    group = User.find_by!(email: "demo@example.com").groups.find_by!(name: DemoSeed::GROUP_NAME)
    expect(group.plantings.pluck(:et_method).uniq).to contain_exactly("pct_cover", "lai")
    expect(group.pivots.map { |pivot| pivot.fields.size }.max).to eq(8)
    expect(PivotIrrigation.where(pivot: group.pivots).where.not(run_hours: nil)).to exist
    expect(group.field_groups.sole.fields.size).to eq(2)
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

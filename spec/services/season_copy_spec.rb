require "rails_helper"

RSpec.describe SeasonCopy do
  let(:group) { create(:group) }
  let(:field) { create(:field, pivot: create(:pivot, farm: create(:farm, group:))) }

  def planting(start, emergence, finish, **attributes)
    create(:planting, field:, season_start: start, emergence_date: emergence, end_date: finish, **attributes)
  end

  it "copies a double crop, both plantings a year later, with their settings" do
    peas = planting(Date.new(2027, 4, 1), Date.new(2027, 4, 20), Date.new(2027, 6, 30), variety: "Early", mad_frac: 0.4)
    planting(Date.new(2027, 7, 1), Date.new(2027, 7, 10), Date.new(2027, 10, 15))

    result = described_class.new(group, 2028).run
    expect(result.failed).to be_empty
    expect(result.copied.map { |copy| [copy.season_start, copy.end_date] }).to eq([
      [Date.new(2028, 4, 1), Date.new(2028, 6, 30)], [Date.new(2028, 7, 1), Date.new(2028, 10, 15)]
    ])
    expect(result.copied.first).to have_attributes(plant_id: peas.plant_id, variety: "Early", mad_frac: 0.4)
  end

  it "copies a vine kill date a year later, and leaves it empty where there's none" do
    potato = create(:plant, key: "potato")
    planting(Date.new(2027, 4, 1), Date.new(2027, 5, 15), Date.new(2027, 9, 30), plant: potato,
      vine_kill_date: Date.new(2027, 9, 8))
    expect(described_class.new(group, 2028).run.copied.sole.vine_kill_date).to eq(Date.new(2028, 9, 8))
  end

  it "moves a leap day to Feb 28" do
    planting(Date.new(2028, 2, 29), Date.new(2028, 4, 1), Date.new(2028, 9, 30))
    expect(described_class.new(group, 2029).run.copied.sole.season_start).to eq(Date.new(2029, 2, 28))
  end

  it "leaves fields that already have a crop this season" do
    planting(Date.new(2027, 4, 1), Date.new(2027, 5, 1), Date.new(2027, 9, 30))
    planting(Date.new(2028, 4, 1), Date.new(2028, 5, 1), Date.new(2028, 9, 30))
    expect(described_class.new(group, 2028).run.copied).to be_empty
  end
end

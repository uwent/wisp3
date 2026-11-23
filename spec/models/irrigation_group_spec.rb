require "rails_helper"

RSpec.describe IrrigationGroup do
  let(:farm) { create(:farm) }
  let(:irrigation_group) { create(:irrigation_group, farm:) }

  it "holds systems on its own farm only" do
    system = create(:system, farm:, irrigation_group:)
    expect(irrigation_group.systems).to eq([system])

    elsewhere = build(:system, farm: create(:farm, group: farm.group), irrigation_group:)
    expect(elsewhere).not_to be_valid
    expect(elsewhere.errors[:irrigation_group]).to include("must be on the same farm")
  end

  it "is kept on the system's farm by the database too" do
    system = create(:system, farm:)
    other_farm = create(:farm, group: farm.group)
    other_group = create(:irrigation_group, farm: other_farm)
    expect { system.update_column(:irrigation_group_id, other_group.id) }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "loses a system moved to another farm" do
    system = create(:system, farm:, irrigation_group:)
    system.update!(farm: create(:farm, group: farm.group))
    expect(system.reload.irrigation_group).to be_nil
  end

  it "ungroups its systems when deleted" do
    system = create(:system, farm:, irrigation_group:)
    irrigation_group.destroy!
    expect(system.reload.irrigation_group_id).to be_nil
  end

  it "goes with its farm" do
    create(:system, farm:, irrigation_group:)
    expect { farm.destroy! }.to change(IrrigationGroup, :count).by(-1).and change(IrrigationSystem, :count).by(-1)
  end
end

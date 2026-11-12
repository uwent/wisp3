require "rails_helper"

RSpec.describe PivotGroup do
  let(:farm) { create(:farm) }
  let(:pivot_group) { create(:pivot_group, farm:) }

  it "holds pivots on its own farm only" do
    pivot = create(:pivot, farm:, pivot_group:)
    expect(pivot_group.pivots).to eq([pivot])

    elsewhere = build(:pivot, farm: create(:farm, group: farm.group), pivot_group:)
    expect(elsewhere).not_to be_valid
    expect(elsewhere.errors[:pivot_group]).to include("must be on the same farm")
  end

  it "is kept on the pivot's farm by the database too" do
    pivot = create(:pivot, farm:)
    other_farm = create(:farm, group: farm.group)
    other_group = create(:pivot_group, farm: other_farm)
    expect { pivot.update_column(:pivot_group_id, other_group.id) }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "loses a pivot moved to another farm" do
    pivot = create(:pivot, farm:, pivot_group:)
    pivot.update!(farm: create(:farm, group: farm.group))
    expect(pivot.reload.pivot_group).to be_nil
  end

  it "ungroups its pivots when deleted" do
    pivot = create(:pivot, farm:, pivot_group:)
    pivot_group.destroy!
    expect(pivot.reload.pivot_group_id).to be_nil
  end

  it "goes with its farm" do
    create(:pivot, farm:, pivot_group:)
    expect { farm.destroy! }.to change(PivotGroup, :count).by(-1).and change(Pivot, :count).by(-1)
  end
end

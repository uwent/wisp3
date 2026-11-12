require "rails_helper"

RSpec.describe "Pivot groups", type: :request do
  let(:user) { create(:user) }
  let(:farm) { create(:farm, group: user.groups.first) }
  let!(:north) { create(:pivot, farm:, name: "North") }
  let!(:south) { create(:pivot, farm:, name: "South") }
  let!(:east) { create(:pivot, farm:, name: "East") }

  before { sign_in user }

  it "creates a group with some of the farm's pivots" do
    post pivot_groups_path, params: {pivot_group: {farm_id: farm.id, name: "Home gauge", pivot_ids: ["", north.id, south.id]}}
    expect(response).to redirect_to(setup_path)
    group = PivotGroup.last
    expect(group.name).to eq("Home gauge")
    expect(group.pivots).to contain_exactly(north, south)
  end

  it "sets exactly the checked pivots, moving one from another group" do
    group = create(:pivot_group, farm:)
    other = create(:pivot_group, farm:)
    north.update!(pivot_group: group)
    east.update!(pivot_group: other)

    patch pivot_group_path(group), params: {pivot_group: {name: "Renamed", pivot_ids: ["", east.id]}}
    expect(group.reload.name).to eq("Renamed")
    expect(group.pivots).to eq([east])
    expect(north.reload.pivot_group).to be_nil
  end

  it "empties a group when nothing is checked" do
    group = create(:pivot_group, farm:)
    north.update!(pivot_group: group)
    patch pivot_group_path(group), params: {pivot_group: {name: group.name, pivot_ids: [""]}}
    expect(group.pivots.reload).to be_empty
  end

  it "needs a name" do
    post pivot_groups_path, params: {pivot_group: {farm_id: farm.id, name: " ", pivot_ids: [""]}}
    expect(response).to redirect_to(setup_path)
    expect(PivotGroup.count).to eq(0)
  end

  it "deletes a group, leaving its pivots" do
    group = create(:pivot_group, farm:)
    north.update!(pivot_group: group)
    delete pivot_group_path(group)
    expect(PivotGroup.count).to eq(0)
    expect(north.reload.pivot_group).to be_nil
  end

  it "shows the groups in Setup", :inertia do
    group = create(:pivot_group, farm:, name: "Home gauge")
    north.update!(pivot_group: group)
    get setup_path
    farm_props = inertia.props[:farms].sole
    expect(farm_props[:pivot_groups]).to eq([{"id" => group.id, "name" => "Home gauge"}])
    expect(farm_props[:pivots].find { |pivot| pivot[:id] == north.id }[:pivot_group_id]).to eq(group.id)
  end

  describe "another operation's" do
    let(:outsider) { create(:user) }
    let(:their_farm) { create(:farm, group: outsider.groups.first) }
    let(:their_pivot) { create(:pivot, farm: their_farm) }
    let(:their_group) { create(:pivot_group, farm: their_farm) }

    before { get root_path } # Devise's test sign_in applies on the first request

    it "groups and farms are hidden" do
      patch pivot_group_path(their_group), params: {pivot_group: {name: "Mine now"}}
      expect(response).to have_http_status(:not_found)
      delete pivot_group_path(their_group)
      expect(response).to have_http_status(:not_found)
      post pivot_groups_path, params: {pivot_group: {farm_id: their_farm.id, name: "Sneaky"}}
      expect(response).to have_http_status(:not_found)
      expect(their_group.reload.name).not_to eq("Mine now")
    end

    it "pivots can't be pulled into my group" do
      group = create(:pivot_group, farm:)
      patch pivot_group_path(group), params: {pivot_group: {name: group.name, pivot_ids: [their_pivot.id, north.id]}}
      expect(their_pivot.reload.pivot_group_id).to be_nil
      expect(group.pivots).to eq([north])
    end
  end
end

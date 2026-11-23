require "rails_helper"

RSpec.describe "Irrigation groups", type: :request do
  let(:user) { create(:user) }
  let(:farm) { create(:farm, group: user.groups.first) }
  let!(:north) { create(:system, farm:, name: "North") }
  let!(:south) { create(:system, farm:, name: "South") }
  let!(:east) { create(:system, farm:, name: "East") }

  before { sign_in user }

  it "creates a group with some of the farm's systems" do
    post irrigation_groups_path, params: {irrigation_group: {farm_id: farm.id, name: "Home gauge", system_ids: ["", north.id, south.id]}}
    expect(response).to redirect_to(setup_path)
    group = IrrigationGroup.last
    expect(group.name).to eq("Home gauge")
    expect(group.systems).to contain_exactly(north, south)
  end

  it "sets exactly the checked systems, moving one from another group" do
    group = create(:irrigation_group, farm:)
    other = create(:irrigation_group, farm:)
    north.update!(irrigation_group: group)
    east.update!(irrigation_group: other)

    patch irrigation_group_path(group), params: {irrigation_group: {name: "Renamed", system_ids: ["", east.id]}}
    expect(group.reload.name).to eq("Renamed")
    expect(group.systems).to eq([east])
    expect(north.reload.irrigation_group).to be_nil
  end

  it "empties a group when nothing is checked" do
    group = create(:irrigation_group, farm:)
    north.update!(irrigation_group: group)
    patch irrigation_group_path(group), params: {irrigation_group: {name: group.name, system_ids: [""]}}
    expect(group.systems.reload).to be_empty
  end

  it "sets the group's rainfall setting, blank following the farm's (Q7)" do
    post irrigation_groups_path, params: {irrigation_group: {farm_id: farm.id, name: "Home gauge", use_model_precip: "false", system_ids: [""]}}
    group = IrrigationGroup.last
    expect(group.use_model_precip).to be(false)
    patch irrigation_group_path(group), params: {irrigation_group: {name: group.name, use_model_precip: "true"}}
    expect(group.reload.use_model_precip).to be(true)
    patch irrigation_group_path(group), params: {irrigation_group: {name: group.name, use_model_precip: ""}}
    expect(group.reload.use_model_precip).to be_nil
  end

  it "needs a name" do
    post irrigation_groups_path, params: {irrigation_group: {farm_id: farm.id, name: " ", system_ids: [""]}}
    expect(response).to redirect_to(setup_path)
    expect(IrrigationGroup.count).to eq(0)
  end

  it "deletes a group, leaving its systems" do
    group = create(:irrigation_group, farm:)
    north.update!(irrigation_group: group)
    delete irrigation_group_path(group)
    expect(IrrigationGroup.count).to eq(0)
    expect(north.reload.irrigation_group).to be_nil
  end

  it "shows the groups in Setup", :inertia do
    group = create(:irrigation_group, farm:, name: "Home gauge")
    north.update!(irrigation_group: group)
    get setup_path
    farm_props = inertia.props[:farms].sole
    expect(farm_props[:irrigation_groups]).to eq([{"id" => group.id, "name" => "Home gauge", "created_by_id" => nil, "use_model_precip" => nil}])
    expect(farm_props[:systems].find { |system| system[:id] == north.id }[:irrigation_group_id]).to eq(group.id)
  end

  describe "another operation's" do
    let(:outsider) { create(:user) }
    let(:their_farm) { create(:farm, group: outsider.groups.first) }
    let(:their_system) { create(:system, farm: their_farm) }
    let(:their_group) { create(:irrigation_group, farm: their_farm) }

    before { get root_path } # Devise's test sign_in applies on the first request

    it "groups and farms are hidden" do
      patch irrigation_group_path(their_group), params: {irrigation_group: {name: "Mine now"}}
      expect(response).to have_http_status(:not_found)
      delete irrigation_group_path(their_group)
      expect(response).to have_http_status(:not_found)
      post irrigation_groups_path, params: {irrigation_group: {farm_id: their_farm.id, name: "Sneaky"}}
      expect(response).to have_http_status(:not_found)
      expect(their_group.reload.name).not_to eq("Mine now")
    end

    it "systems can't be pulled into my group" do
      group = create(:irrigation_group, farm:)
      patch irrigation_group_path(group), params: {irrigation_group: {name: group.name, system_ids: [their_system.id, north.id]}}
      expect(their_system.reload.irrigation_group_id).to be_nil
      expect(group.systems).to eq([north])
    end
  end
end

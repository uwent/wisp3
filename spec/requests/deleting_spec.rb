require "rails_helper"

# Who may delete what (Q8): owners anything; a member only the plantings and irrigation
# groups they added, never a farm, system or field, whose deletes reach everyone's records
RSpec.describe "Deleting as a member", type: :request do
  let(:owner) { create(:user) }
  let(:group) { owner.groups.first }
  let(:member) { create(:user) }
  let(:farm) { create(:farm, group:) }
  let(:pivot) { create(:pivot, farm:) }
  let(:field) { create(:field, pivot:) }
  let(:potato) { create(:plant, key: "potato", name: "Potato") }

  before do
    create(:membership, group:, user: member)
    sign_in member
    get root_path # Devise's test sign_in applies on the first request
    patch current_group_path, params: {group_id: group.id}
  end

  around { |example| travel_to(Date.new(2026, 7, 20)) { example.run } }

  it "can't delete a farm, an irrigation system or a field" do
    delete field_path(field)
    delete pivot_path(pivot)
    delete farm_path(farm)
    expect(flash[:alert]).to include("Only an owner")
    expect([farm, pivot, field].map { |record| record.class.exists?(record.id) }).to all(be(true))
  end

  it "deletes the plantings they added, not others'" do
    post plantings_path(year: 2026), params: {planting: {field_id: field.id, plant_id: potato.id,
                                                         season_start: "2026-04-15", emergence_date: "2026-05-01", end_date: "2026-06-01"}}
    mine = field.plantings.sole
    expect(mine.created_by).to eq(member)
    theirs = create(:planting, field:, plant: potato, season_start: Date.new(2026, 6, 10),
      emergence_date: Date.new(2026, 6, 15), end_date: Date.new(2026, 9, 1), created_by: owner)
    before = create(:planting, field:, plant: potato, season_start: Date.new(2025, 5, 1),
      emergence_date: Date.new(2025, 5, 15), end_date: Date.new(2025, 9, 1))

    delete planting_path(theirs)
    expect(flash[:alert]).to include("or the person who added it")
    delete planting_path(before) # added before creators were recorded: owners only
    delete planting_path(mine)
    expect(field.plantings.reload).to contain_exactly(theirs, before)
  end

  it "deletes the irrigation groups they added, not others'" do
    post pivot_groups_path, params: {pivot_group: {farm_id: farm.id, name: "Mine", pivot_ids: [""]}}
    mine = farm.pivot_groups.find_by!(name: "Mine")
    expect(mine.created_by).to eq(member)
    theirs = create(:pivot_group, farm:, name: "Theirs", created_by: owner)

    delete pivot_group_path(theirs)
    delete pivot_group_path(mine)
    expect(farm.pivot_groups.reload).to eq([theirs])
  end

  it "records who copied last season" do
    create(:planting, field:, plant: potato, season_start: Date.new(2025, 5, 1),
      emergence_date: Date.new(2025, 5, 15), end_date: Date.new(2025, 9, 1))
    post season_copy_path(year: 2026)
    expect(field.plantings.find_by!(season_start: Date.new(2026, 5, 1)).created_by).to eq(member)
  end
end

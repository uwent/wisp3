require "rails_helper"

# A farm operation's page, members and roles (Q8)
RSpec.describe "Farm operations", type: :request do
  let(:owner) { create(:user, first_name: "Olive", last_name: "Owner", email: "olive@example.com") }
  let(:group) { owner.groups.first }
  let(:member) { create(:user, first_name: "Max", last_name: "Member", email: "max@example.com") }
  let!(:member_membership) { create(:membership, group:, user: member) }
  let(:owner_membership) { group.memberships.find_by!(user: owner) }

  def sign_in_to(user, group)
    sign_in user
    get root_path # Devise's test sign_in applies on the first request
    patch current_group_path, params: {group_id: group.id}
  end

  describe "the page" do
    it "shows the members, the setup counts and the user's operations" do
      create(:field, pivot: create(:pivot, farm: create(:farm, group:)))
      sign_in_to(member, group)
      get group_path
      expect_inertia.to render_component("Groups/Show")
      expect(inertia.props[:members].map { |m| [m[:email], m[:owner]] }).to eq([["olive@example.com", true], ["max@example.com", false]])
      expect(inertia.props[:membership_id]).to eq(member_membership.id)
      expect(inertia.props[:counts]).to eq("farms" => 1, "pivots" => 1, "fields" => 1)
      expect(inertia.props[:operations].map { |o| o[:name] }).to contain_exactly(group.name, member.groups.where.not(id: group.id).sole.name)
      expect(inertia.props[:auth][:owner]).to be(false)
    end
  end

  describe "settings" do
    it "lets an owner rename the operation and change its rainfall" do
      sign_in_to(owner, group)
      patch group_path, params: {group: {name: "Sands Farms", use_model_precip: "false"}}
      expect(group.reload).to have_attributes(name: "Sands Farms", use_model_precip: false)
    end

    it "keeps members from changing them" do
      sign_in_to(member, group)
      patch group_path, params: {group: {name: "Mine now"}}
      expect(flash[:alert]).to include("Only an owner")
      expect(group.reload.name).not_to eq("Mine now")
    end
  end

  describe "adding members" do
    let(:newcomer) { create(:user, email: "new@example.com") }

    before { sign_in_to(owner, group) }

    it "adds an existing account by its email and tells them" do
      newcomer
      expect { post memberships_path, params: {membership: {email: " NEW@example.com ", owner: "true"}} }
        .to have_enqueued_mail(MembershipMailer, :added)
      expect(group.memberships.find_by!(user: newcomer)).to be_owner
      expect(flash[:notice]).to include("Added")
    end

    it "needs an account that exists, is confirmed and isn't a member already" do
      create(:user, :unconfirmed, email: "pending@example.com")
      {"nobody@example.com" => "No WISP account", "pending@example.com" => "hasn't confirmed",
       "max@example.com" => "already a member", "" => "Enter the email"}.each do |email, message|
        expect { post memberships_path, params: {membership: {email:}} }.not_to change(Membership, :count)
        follow_redirect!
        expect(inertia.props.dig(:errors, :email)).to include(a_string_including(message)), email
      end
    end

    it "is for owners only" do
      sign_in_to(member, group)
      newcomer
      expect { post memberships_path, params: {membership: {email: "new@example.com"}} }.not_to change(Membership, :count)
    end
  end

  describe "roles" do
    it "lets an owner make a member an owner, and back" do
      sign_in_to(owner, group)
      patch membership_path(member_membership), params: {membership: {owner: "true"}}
      expect(member_membership.reload).to be_owner
      patch membership_path(member_membership), params: {membership: {owner: "false"}}
      expect(member_membership.reload).not_to be_owner
    end

    it "keeps the last owner" do
      sign_in_to(owner, group)
      patch membership_path(owner_membership), params: {membership: {owner: "false"}}
      expect(owner_membership.reload).to be_owner
      expect(flash[:alert]).to include("only owner")
    end

    it "is for owners only" do
      sign_in_to(member, group)
      patch membership_path(member_membership), params: {membership: {owner: "true"}}
      expect(member_membership.reload).not_to be_owner
    end
  end

  describe "removing and leaving" do
    it "lets an owner remove a member" do
      sign_in_to(owner, group)
      expect { delete membership_path(member_membership) }.to change(group.memberships, :count).by(-1)
      expect(response).to redirect_to(group_path)
    end

    it "lets a member leave, but not remove anyone else" do
      sign_in_to(member, group)
      expect { delete membership_path(owner_membership) }.not_to change(Membership, :count)
      expect { delete membership_path(member_membership) }.to change(group.memberships, :count).by(-1)
      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(inertia.props[:auth][:group][:id]).not_to eq(group.id)
    end

    it "keeps the last owner, and the only member" do
      sign_in_to(owner, group)
      expect { delete membership_path(owner_membership) }.not_to change(Membership, :count)
      expect(flash[:alert]).to include("only owner")
      member_membership.destroy!
      expect { delete membership_path(owner_membership) }.not_to change(Membership, :count)
      expect(flash[:alert]).to include("only member")
    end

    it "gives someone removed from their last operation a new one of their own" do
      member.memberships.where.not(group:).destroy_all
      sign_in_to(owner, group)
      delete membership_path(member_membership)
      sign_in_to(member, group)
      expect(member.reload.groups.sole).to have_attributes(name: "Max Member's farms")
      expect(member.memberships.sole).to be_owner
    end
  end

  describe "creating and deleting operations" do
    it "creates an operation owned by its creator and switches to it" do
      sign_in_to(member, group)
      post groups_path, params: {group: {name: "Second farm"}}
      created = Group.find_by!(name: "Second farm")
      expect(created.memberships.sole).to have_attributes(user_id: member.id, owner: true)
      get group_path
      expect(inertia.props[:auth][:group][:id]).to eq(created.id)
    end

    it "lets an owner delete the operation with its farms" do
      create(:field, pivot: create(:pivot, farm: create(:farm, group:)))
      sign_in_to(owner, group)
      expect { delete group_path }.to change(Group, :count).by(-1).and change(Field, :count).by(-1)
      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(inertia.props[:auth][:group]).to be_present
    end

    it "keeps members from deleting it" do
      sign_in_to(member, group)
      expect { delete group_path }.not_to change(Group, :count)
    end
  end

  describe "deleting farms, pivots and fields" do
    let!(:field) { create(:field, pivot: create(:pivot, farm: create(:farm, group:))) }

    it "is for owners only" do
      sign_in_to(member, group)
      expect { delete field_path(field) }.not_to change(Field, :count)
      expect { delete pivot_path(field.pivot) }.not_to change(Pivot, :count)
      expect { delete farm_path(field.farm) }.not_to change(Farm, :count)
      expect(flash[:alert]).to include("Only an owner")

      sign_in_to(owner, group)
      expect { delete farm_path(field.farm) }.to change(Field, :count).by(-1)
    end
  end

  it "can't reach another operation's members" do
    outsider = create(:user)
    theirs = outsider.memberships.sole
    sign_in_to(owner, group)
    patch membership_path(theirs), params: {membership: {owner: "false"}}
    expect(response).to have_http_status(:not_found)
    delete membership_path(theirs)
    expect(response).to have_http_status(:not_found)
    expect(theirs.reload).to be_owner
  end

  it "hands a deleted account's operation to its longest-standing member" do
    later = create(:user)
    create(:membership, group:, user: later)
    owner.destroy!
    expect(member_membership.reload).to be_owner
    expect(group.memberships.find_by!(user: later)).not_to be_owner
  end
end

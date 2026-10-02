require "rails_helper"

RSpec.describe "Groups and settings", type: :request do
  let(:password) { "correct horse battery" }
  let(:user) { create(:user, password:) }

  before { sign_in user }

  describe "current group" do
    it "defaults to the user's own group and shares it with every page" do
      get root_path
      expect(inertia.props.dig(:auth, :group, :id)).to eq(user.groups.first.id)
      expect(inertia.props.dig(:auth, :user, :email)).to eq(user.email)
    end

    it "switches to another group the user belongs to" do
      other = create(:group, name: "Shared farm")
      create(:membership, user:, group: other)

      patch current_group_path, params: {group_id: other.id}
      follow_redirect!
      expect(inertia.props.dig(:auth, :group, :name)).to eq("Shared farm")
      expect(inertia.props.dig(:auth, :groups).size).to eq(2)
    end

    it "refuses to switch into someone else's group" do
      outsider = create(:user)
      get root_path # establish the session (Devise's test sign_in applies on the first request)
      patch current_group_path, params: {group_id: outsider.groups.first.id}
      expect(response).to have_http_status(:not_found)

      get root_path
      expect(inertia.props.dig(:auth, :group, :id)).to eq(user.groups.first.id)
    end

    it "falls back to a group the user belongs to after losing access" do
      other = create(:group)
      membership = create(:membership, user:, group: other)
      patch current_group_path, params: {group_id: other.id}
      membership.destroy!

      get root_path
      expect(inertia.props.dig(:auth, :group, :id)).to eq(user.groups.first.id)
    end
  end

  describe "settings" do
    it "updates name and units" do
      patch settings_path, params: {user: {first_name: "Sam", last_name: "Field", unit_system: "metric"}}
      expect(response).to redirect_to(settings_path)
      expect(user.reload).to have_attributes(first_name: "Sam", unit_system: "metric")
    end

    it "does not let profile updates change the email or admin flag" do
      patch settings_path, params: {user: {first_name: "Sam", email: "x@example.com", admin: true}}
      expect(user.reload).to have_attributes(email: user.email, admin: false)
    end

    it "sends validation errors back to the page" do
      patch settings_path, params: {user: {unit_system: "furlongs"}}
      follow_redirect!
      expect(inertia.props[:errors]).to include("unit_system")
    end

    it "requires the current password to change the password" do
      patch user_registration_path, params: {user: {password: "a brand new one", password_confirmation: "a brand new one", current_password: "wrong"}}
      expect(response).to redirect_to(settings_path)
      follow_redirect!
      expect(inertia.props[:errors]).to include("current_password")

      patch user_registration_path, params: {user: {password: "a brand new one", password_confirmation: "a brand new one", current_password: password}}
      expect(response).to redirect_to(settings_path)
      expect(user.reload.valid_password?("a brand new one")).to be(true)
    end

    it "deletes the account" do
      delete user_registration_path
      expect(User.exists?(user.id)).to be(false)
    end
  end
end

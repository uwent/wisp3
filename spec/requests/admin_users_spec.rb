require "rails_helper"

RSpec.describe "Admin users", type: :request do
  let(:admin) { create(:user, admin: true, email: "staff@example.com") }

  it "is hidden from users who aren't admins" do
    user = create(:user)
    other = create(:user, :unconfirmed)
    sign_in user
    get root_path
    get admin_users_path
    expect(response).to have_http_status(:not_found)
    get admin_user_path(other)
    expect(response).to have_http_status(:not_found)
    expect { delete admin_user_path(other) }.not_to change(User, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "requires signing in" do
    get admin_users_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "lists every account with its farm, pivot and field counts over its groups" do
    grower = create(:user, email: "grower@example.com")
    shared = create(:group)
    create(:membership, user: grower, group: shared)
    create(:field, pivot: create(:pivot, farm: create(:farm, group: grower.groups.first)))
    create_list(:field, 2, pivot: create(:pivot, farm: create(:farm, group: shared)))
    create(:user, :unconfirmed, email: "new@example.com")

    sign_in admin
    get admin_users_path
    expect_inertia.to render_component("Admin/Users/Index")
    users = inertia.props[:users].index_by { |user| user[:email] }
    expect(users.keys).to contain_exactly("staff@example.com", "grower@example.com", "new@example.com")
    expect(users["grower@example.com"]).to include(confirmed: true, farms_count: 2, pivots_count: 2, fields_count: 3)
    expect(users["new@example.com"]).to include(confirmed: false, farms_count: 0, current_sign_in_at: nil)
  end

  it "shows an account's details and farm structure, without its secrets" do
    grower = create(:user, email: "grower@example.com")
    planting = create(:planting, field: create(:field, name: "North",
      pivot: create(:pivot, name: "Home", farm: create(:farm, name: "Hancock", group: grower.groups.first))))

    sign_in admin
    get admin_user_path(grower)
    expect_inertia.to render_component("Admin/Users/Show")
    expect(inertia.props[:user]).to include(id: grower.id, email: "grower@example.com", sign_in_count: 0)
    expect(inertia.props[:user].keys).not_to include(:encrypted_password, :confirmation_token, :reset_password_token,
      :sign_in_code_digest)
    expect(inertia.props[:deletable]).to be(true)
    group = inertia.props[:groups].sole
    expect(group[:members]).to eq([{"id" => grower.id, "email" => "grower@example.com", "owner" => true}])
    farm = group[:farms].sole
    expect(farm[:name]).to eq("Hancock")
    expect(farm[:pivots].sole[:fields].sole).to include(name: "North")
    expect(farm[:pivots].sole[:fields].sole[:plantings].sole).to include(id: planting.id, plant_name: "Potato")
  end

  it "deletes an account with the groups only it belongs to, keeping shared groups" do
    grower = create(:user)
    own = grower.groups.first
    create(:field, pivot: create(:pivot, farm: create(:farm, group: own)))
    shared = create(:group)
    create(:membership, user: grower, group: shared)
    create(:membership, user: create(:user), group: shared)

    sign_in admin
    expect { delete admin_user_path(grower) }.to change(User, :count).by(-1).and change(Field, :count).by(-1)
    expect(response).to redirect_to(admin_users_path)
    expect(flash[:notice]).to eq("Deleted #{grower.email}.")
    expect(Group.exists?(own.id)).to be(false)
    expect(Group.exists?(shared.id)).to be(true)
  end

  it "won't delete the admin's own account or another admin's" do
    other_admin = create(:user, admin: true)
    sign_in admin
    [admin, other_admin].each do |user|
      expect { delete admin_user_path(user) }.not_to change(User, :count)
      expect(response).to redirect_to(admin_user_path(user))
    end
    get admin_user_path(other_admin)
    expect(inertia.props[:deletable]).to be(false)
  end
end

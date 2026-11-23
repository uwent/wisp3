require "rails_helper"

RSpec.describe "Admin users", type: :request do
  let(:admin) { create(:user, admin: true, email: "staff@example.com") }

  it "lists every account with its farm, system and field counts over its groups" do
    grower = create(:user, email: "grower@example.com")
    shared = create(:group)
    create(:membership, user: grower, group: shared)
    create(:field, system: create(:system, farm: create(:farm, group: grower.groups.first)))
    create_list(:field, 2, system: create(:system, farm: create(:farm, group: shared)))
    create(:user, :unconfirmed, email: "new@example.com")

    sign_in admin
    get admin_users_path
    expect_inertia.to render_component("Admin/Users/Index")
    users = inertia.props[:users].index_by { |user| user[:email] }
    expect(users.keys).to contain_exactly("staff@example.com", "grower@example.com", "new@example.com")
    expect(users["grower@example.com"]).to include(confirmed: true, farms_count: 2, systems_count: 2, fields_count: 3,
      plantings_season_count: 0, last_active_on: nil)
    expect(users["new@example.com"]).to include(confirmed: false, farms_count: 0, current_sign_in_at: nil)
  end

  it "exports every account as a CSV with its counts, activity and the bounds of its systems" do
    travel_to Time.zone.local(2026, 7, 20, 9)
    grower = create(:user, email: "grower@example.com", first_name: "=Jane", digest_frequency: "daily")
    shared = create(:group)
    create(:membership, user: grower, group: shared)
    north = create(:system, latitude: 44.5, longitude: -89.9, farm: create(:farm, group: grower.groups.first))
    south = create(:system, latitude: 43.25, longitude: -89.1, farm: create(:farm, group: shared))
    create(:planting, field: create(:field, system: north))
    create(:planting, field: create(:field, system: south), season_start: Date.new(2025, 4, 1),
      emergence_date: Date.new(2025, 5, 15), end_date: Date.new(2025, 9, 30))
    [Date.new(2025, 8, 1), Date.new(2026, 6, 1), Date.new(2026, 7, 2)].each do |date|
      ActivityDay.record(grower, date:, area: "dashboard")
    end
    create(:user, :unconfirmed, email: "new@example.com")

    sign_in admin
    get export_admin_users_path
    expect(response.media_type).to eq("text/csv")
    expect(response.headers["Content-Disposition"]).to include("wisp-accounts-2026-07-20.csv")
    rows = CSV.parse(response.body.delete_prefix(CsvExport::BOM))
    expect(rows.first).to eq(["WISP accounts"])
    expect(rows).to include(["Accounts: 3"])
    header_at = rows.index { |row| row.first == "ID" }
    records = rows[(header_at + 1)..].map { |row| rows[header_at].zip(row).to_h }.index_by { |row| row["Email"] }
    expect(records.keys).to contain_exactly("staff@example.com", "grower@example.com", "new@example.com")
    expect(records["grower@example.com"]).to include("First name" => "'=Jane", "Daily digest" => "daily",
      "Last active" => "2026-07-02", "Days active (2026)" => "2", "Operations" => "2", "Operations owned" => "1",
      "Farms" => "2", "Irrigation systems" => "2", "Fields" => "2", "Plantings (2026)" => "1",
      "Plantings (all seasons)" => "2", "South latitude" => "43.2500", "West longitude" => "-89.9000",
      "North latitude" => "44.5000", "East longitude" => "-89.1000")
    expect(records["new@example.com"]).to include("Confirmed" => nil, "Last active" => nil, "Farms" => "0",
      "South latitude" => nil)
  end

  it "shows an account's details and farm structure, without its secrets" do
    grower = create(:user, email: "grower@example.com")
    planting = create(:planting, field: create(:field, name: "North",
      system: create(:system, name: "Home", farm: create(:farm, name: "Hancock", group: grower.groups.first))))

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
    expect(farm[:systems].sole[:fields].sole).to include(name: "North")
    expect(farm[:systems].sole[:fields].sole[:plantings].sole).to include(id: planting.id, plant_name: "Potato")
  end

  it "shows an account's farms without queries per farm, field or planting" do
    grower = create(:user)
    add_farm = lambda do
      farm = create(:farm, group: grower.groups.first)
      create(:irrigation_group, farm:, systems: [create(:system, farm:)])
      create(:planting, field: create(:field, system: farm.systems.first))
    end
    queries = lambda do
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get admin_user_path(grower) }
      count
    end
    add_farm.call
    sign_in admin
    get admin_user_path(grower)
    one = queries.call
    2.times { add_farm.call }
    expect(queries.call).to eq(one)
  end

  it "deletes an account with the groups only it belongs to, keeping shared groups" do
    grower = create(:user)
    own = grower.groups.first
    create(:field, system: create(:system, farm: create(:farm, group: own)))
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

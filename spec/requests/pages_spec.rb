require "rails_helper"

RSpec.describe "Public pages", type: :request do
  it "shows the landing page signed out, and the dashboard signed in" do
    get root_path
    expect_inertia.to render_component("Pages/Home")
    expect(inertia.props[:auth][:user]).to be_nil

    sign_in create(:user)
    get root_path
    expect_inertia.to render_component("Dashboard/Show")
  end

  it "shows the About page to anyone, with every crop" do
    create(:plant, key: "field_corn", name: "Field Corn", default_max_root_zone_depth: 33, canopy_model: "field_corn")
    get about_path
    expect_inertia.to render_component("Pages/About")
    expect(inertia.props[:plants]).to include({key: "field_corn", name: "Field Corn", root_zone_in: 33.0, lai_curve: true})
    expect(inertia.props[:defaults]).to eq("mad_pct" => 50, "lead_days" => 3, "forecast_days" => 16)
  end

  it "keeps the signed-in user's operation on the About page" do
    user = create(:user)
    other = create(:group, name: "Partners")
    create(:membership, user:, group: other)
    sign_in user
    patch current_group_path, params: {group_id: other.id}
    get about_path
    expect(inertia.props[:auth][:group][:id]).to eq(other.id)
  end
end

require "rails_helper"

RSpec.describe "Public pages", type: :request do
  it "shows the About page to anyone, with every crop" do
    create(:plant, key: "field_corn", name: "Field Corn", default_max_root_zone_depth: 33, canopy_model: "field_corn")
    get about_path
    expect_inertia.to render_component("Pages/About")
    expect(inertia.props[:plants]).to include({key: "field_corn", name: "Field Corn", root_zone_in: 33.0, lai_curve: true,
      cover_curve: true})
    expect(inertia.props[:defaults]).to eq("mad_pct" => 50, "lead_days" => 3, "forecast_days" => 16,
      "shift_warning_days" => 7, "drop_warning" => 5)
  end

  it "documents each crop's canopy curve, with its sources" do
    create(:plant, key: "potato", name: "Potato")
    create(:plant, key: "onion", name: "Onion")
    get about_path
    curves = inertia.props[:canopy_curves]
    expect(curves.map { |curve| curve[:key] }).to eq(["potato"])
    expect(curves.first).to include(confidence: "matches_wi", days_to: {"50" => 24, "80" => 31},
      decline: {"type" => "rule", "date" => "07-25", "days" => 42, "floor" => 50})
    expect(curves.first[:covers].size).to eq(PagesController::CURVE_DAYS + 1)
    expect(curves.first[:sources].map { |source| source[:url] }).to include("https://doi.org/10.2134/agronj2008.0139s")
  end

  it "tabulates the soil types with where their values come from" do
    ReferenceData.load!
    get about_path
    soils = inertia.props[:soil_types]
    expect(soils.size).to eq(11)
    sand = {key: "sand", name: "Sand", field_capacity: 0.1, perm_wilting_pt: 0.04, basis: "legacy_confirmed"}
    expect(soils.first).to eq(sand.stringify_keys)
    expect(soils.find { |soil| soil[:key] == "muck" }).to include(field_capacity: 0.53, basis: "wi_survey")
    expect(soils.map { |soil| soil[:basis] }).to all(be_present)
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

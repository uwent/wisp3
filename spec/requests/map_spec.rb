require "rails_helper"

RSpec.describe "Map", type: :request do
  let(:user) { create(:user) }
  let(:farm) { create(:farm, group: user.groups.first, name: "Hancock Sands") }
  let(:pivot) do
    create(:pivot, farm:, name: "North 160", latitude: 44.1335, longitude: -89.5213, radius_ft: 1300,
      arc_start_deg: 30, arc_end_deg: 300)
  end
  let(:field) { create(:field, pivot:, name: "North potatoes") }

  before do
    create(:planting, field:, season_start: Date.new(2026, 5, 1), emergence_date: Date.new(2026, 5, 20),
      end_date: Date.new(2026, 9, 15))
    (Date.new(2026, 5, 1)..Date.new(2026, 7, 19)).each do |date|
      pivot.weather_cell.weather_days.create!(date:, et0_in: 0.2, precip_in: (date.day == 15) ? 0.5 : 0.0,
        tmax_f: 85, tmin_f: 60, model: "ncep_nbm_conus", hours: 24, fetched_at: Time.current)
    end
    sign_in user
  end

  around { |example| travel_to(Time.zone.local(2026, 7, 20, 9)) { example.run } }

  it "gives each pivot its location, its weather zone's last week and its fields' cards" do
    get map_path
    expect_inertia.to render_component("Map/Show")
    shown = inertia.props[:farms].sole[:pivots].sole
    expect(shown).to include(id: pivot.id, name: "North 160", latitude: 44.1335, longitude: -89.5213, radius_ft: 1300,
      arc_start_deg: 30, arc_end_deg: 300)
    expect(shown[:weather][:past]).to include(days: 7, precip: 0.5)
    expect(shown[:weather][:past][:et0]).to be_within(1e-9).of(1.4)
    expect(shown[:weather][:ahead]).to be_nil # no forecast stored
    card = shown[:fields].sole
    expect(card).to include(id: field.id, name: "North potatoes")
    expect(card[:summary]).to include(phase: "active")
  end

  it "shows only the current operation's pivots" do
    outsider = create(:user)
    create(:pivot, farm: create(:farm, group: outsider.groups.first), name: "Their pivot")
    get map_path
    names = inertia.props[:farms].flat_map { |f| f[:pivots] }.map { |p| p[:name] }
    expect(names).to eq(["North 160"])
  end

  it "needs a signed-in user" do
    sign_out user
    get map_path
    expect(response).to redirect_to(new_user_session_path)
  end
end

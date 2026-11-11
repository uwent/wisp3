require "rails_helper"

RSpec.describe "Canopy cuttings (G.3)", type: :request do
  let(:user) { create(:user) }
  let(:field) { create(:field, pivot: create(:pivot, farm: create(:farm, group: user.groups.first))) }
  let(:planting) do
    create(:planting, field:, plant: create(:plant, key: "alfalfa", name: "Alfalfa"), season_start: Date.new(2026, 4, 1),
      emergence_date: Date.new(2026, 4, 15), end_date: Date.new(2026, 10, 15))
  end

  before { sign_in user }
  around { |example| travel_to(Time.zone.local(2026, 7, 20, 9)) { example.run } }

  it "adds a cutting from the planting's page, shows it there, and removes it" do
    post planting_cuttings_path(planting), params: {cutting: {date: "2026-06-01"}}
    expect(response).to redirect_to(planting_path(planting))
    get planting_path(planting)
    expect(inertia.props[:planting]).to include(takes_cuttings: true)
    expect(inertia.props[:planting][:cuttings].map { |c| c[:date] }).to eq(["2026-06-01"])
    day = inertia.props[:days].find { |d| d[:date] == "2026-06-01" }
    expect(day[:canopy]).to be_within(0.1).of(5.0)

    delete planting_cutting_path(planting, planting.canopy_cuttings.sole)
    expect(planting.canopy_cuttings).to be_empty
  end

  it "refuses a cutting outside the season or twice on a day" do
    post planting_cuttings_path(planting), params: {cutting: {date: "2026-04-10"}}, headers: {"HTTP_REFERER" => planting_url(planting)}
    planting.canopy_cuttings.create!(date: Date.new(2026, 6, 1))
    post planting_cuttings_path(planting), params: {cutting: {date: "2026-06-01"}}
    follow_redirect!
    expect(inertia.props[:errors]).to include("date")
    expect(planting.canopy_cuttings.count).to eq(1)
  end
end

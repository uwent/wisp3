require "rails_helper"

# The admin Usage page (UsageReport); access for everyone else is in access_spec.rb
RSpec.describe "Admin usage", type: :request do
  it "shows the season asked for, or the current one" do
    sign_in create(:user, admin: true)
    travel_to(Time.zone.parse("2026-07-20 12:00")) do
      get admin_usage_path
      expect_inertia.to render_component("Admin/Usage")
      expect(inertia.props).to include(year: 2026, years: [2026])
      expect(inertia.props[:funnel].map { |step| step[:key] }).to eq(%w[signed_up confirmed farm planting entry regular])

      get admin_usage_path(year: 2025)
      expect(inertia.props[:year]).to eq(2025)
      expect(inertia.props[:weeks].first).to eq("2025-02-24")
    end
  end
end

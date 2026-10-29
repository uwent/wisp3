require "rails_helper"

# Every signed-in route, read from the routes, so a new one is covered as soon as it's added:
# signed-out visitors are sent to sign in (downloads get a 401, as Devise answers a non-page format),
# and admin routes are a 404 for everyone but admins.
RSpec.describe "Access", type: :request do
  routes = Rails.application.routes.routes.filter_map do |route|
    controller = route.defaults[:controller] or next
    klass = "#{controller}_controller".camelize.safe_constantize
    next unless klass && klass < AuthenticatedController
    # Public pages (PagesController) skip sign-in; signed out, / is the landing page
    next if klass._process_action_callbacks.none? { |callback| callback.filter == :authenticate_user! }
    next if route.path.spec.to_s == "/"

    path = route.path.spec.to_s.delete_suffix("(.:format)").gsub(":date", "2026-07-01").gsub(/:\w+/, "1")
    {verb: route.verb.downcase.to_sym, path:, admin: klass < Admin::BaseController, download: route.defaults.key?(:format)}
  end.uniq.freeze

  def visit(route) = public_send(route[:verb], route[:path])

  it "finds the routes to check" do
    expect(routes.size).to be > 40
    expect(routes.count { |route| route[:admin] }).to be >= 6
    expect(routes.count { |route| route[:download] }).to be >= 3
  end

  it "sends signed-out visitors to sign in" do
    routes.each do |route|
      visit(route)
      label = "#{route[:verb].upcase} #{route[:path]}: #{response.status}"
      if route[:download]
        expect(response).to have_http_status(:unauthorized), label
      else
        expect(response).to redirect_to(new_user_session_path), label
      end
    end
  end

  it "hides admin routes from users who aren't admins" do
    sign_in create(:user)
    get root_path # Devise's test sign_in applies on the first request; a 404 wouldn't save the session
    routes.select { |route| route[:admin] }.each do |route|
      expect { visit(route) }.not_to change(User, :count)
      expect(response).to have_http_status(:not_found), "#{route[:verb].upcase} #{route[:path]}: #{response.status}"
    end
  end
end

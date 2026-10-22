require "rails_helper"

RSpec.describe "Request limits (Rack::Attack)", type: :request do
  # Localhost is safelisted, so each request comes from an outside address
  let(:addresses) { (1..20).map { |n| "203.0.113.#{n}" } }
  let!(:user) { create(:user, email: "grower@example.com", password: "right-password-1") }

  def sign_in_from(ip, email:, password: "wrong-password", as: nil)
    post user_session_path, params: {user: {email:, password:}}, env: {"REMOTE_ADDR" => ip, "HTTP_USER_AGENT" => "Mozilla/5.0"}, as:
  end

  it "limits password guesses at one account from many addresses, sent as Inertia's JSON" do
    10.times { |n| sign_in_from(addresses[n], email: "Grower@Example.com ", as: :json) }
    expect(response).to have_http_status(:unauthorized) # a wrong password, not yet limited

    sign_in_from(addresses[10], email: "grower@example.com", password: "right-password-1", as: :json)
    expect(response).to have_http_status(:too_many_requests)
    expect(response.body).to include("sign in with an emailed link")
  end

  it "counts form posts too, and other accounts separately" do
    10.times { |n| sign_in_from(addresses[n], email: "grower@example.com") }
    sign_in_from(addresses[10], email: "grower@example.com")
    expect(response).to have_http_status(:too_many_requests)

    sign_in_from(addresses[11], email: "someone@example.com")
    expect(response).not_to have_http_status(:too_many_requests)
  end

  it "lifts the limit after 15 minutes" do
    11.times { |n| sign_in_from(addresses[n], email: "grower@example.com") }
    travel 16.minutes do
      sign_in_from(addresses[12], email: "grower@example.com", password: "right-password-1")
      expect(response).not_to have_http_status(:too_many_requests)
    end
  end
end

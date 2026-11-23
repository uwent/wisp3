require "rails_helper"

RSpec.describe "Content Security Policy", type: :request do
  it "allows scripts only from WISP, and gives the inline theme script this request's nonce" do
    get root_path
    policy = response.headers["Content-Security-Policy"]
    nonce = policy[/'nonce-([^']+)'/, 1]
    expect(policy).to include("script-src 'self' 'nonce-", "object-src 'none'", "frame-ancestors 'none'")
    expect(policy).not_to match(/script-src[^;]*unsafe-(inline|eval)/)
    expect(response.body).to include(%(<script nonce="#{nonce}">))
  end

  # Google Analytics: the measurement ID's meta tag, which lib/analytics.ts starts from,
  # only when GA_MEASUREMENT_ID is set (production); the script host is allowed then too, at boot
  it "names the Google Analytics measurement ID only when it's configured" do
    get root_path
    expect(response.body).not_to include("ga-measurement-id")
    expect(response.headers["Content-Security-Policy"]).not_to include("googletagmanager")

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GA_MEASUREMENT_ID").and_return("G-TEST123")
    get root_path
    expect(response.body).to include(%(<meta name="ga-measurement-id" content="G-TEST123">))
  end
end

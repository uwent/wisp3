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
end

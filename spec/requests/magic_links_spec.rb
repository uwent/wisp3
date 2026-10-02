require "rails_helper"

RSpec.describe "Sign-in links", type: :request do
  let!(:user) { create(:user) }

  def request_link(email = user.email)
    perform_enqueued_jobs { post magic_links_path, params: {email:} }
  end

  def emailed_token
    ActionMailer::Base.deliveries.last.body.encoded[%r{/account/sign_in_link/([^"\s]+)}, 1]
  end

  it "emails a link and signs in with it" do
    request_link
    expect(response).to redirect_to(new_user_session_path(email: user.email))
    expect(ActionMailer::Base.deliveries.last.to).to eq([user.email])

    post redeem_magic_link_path(token: emailed_token)
    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect_inertia.to render_component("Dashboard/Show")
  end

  it "gives the same response for unknown addresses and sends nothing" do
    request_link("nobody@example.com")
    expect(flash[:notice]).to match(/If there's an account for nobody@example.com/)
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "matches the address case-insensitively" do
    request_link(user.email.upcase)
    expect(ActionMailer::Base.deliveries.last.to).to eq([user.email])
  end

  it "requires an email address" do
    post magic_links_path, params: {email: ""}
    follow_redirect!
    expect(inertia.props[:errors]).to include("email")
  end

  it "does not sign in on GET, so link scanners can't use it up" do
    request_link
    get magic_link_path(token: emailed_token)
    expect_inertia.to render_component("Auth/MagicLink")
    expect(inertia.props[:valid]).to be(true)

    get root_path
    expect(response).to redirect_to(new_user_session_path)

    post redeem_magic_link_path(token: emailed_token)
    expect(response).to redirect_to(root_path)
  end

  it "works only once" do
    request_link
    token = emailed_token
    post redeem_magic_link_path(token:)
    delete destroy_user_session_path

    post redeem_magic_link_path(token:)
    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to match(/expired or was already used/)
  end

  it "expires after 15 minutes" do
    request_link
    token = emailed_token
    travel 16.minutes do
      get magic_link_path(token:)
      expect(inertia.props[:valid]).to be(false)
      post redeem_magic_link_path(token:)
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  it "rejects a tampered token" do
    post redeem_magic_link_path(token: "not-a-real-token")
    expect(response).to redirect_to(new_user_session_path)
  end

  it "confirms an unconfirmed account" do
    unconfirmed = create(:user, :unconfirmed)
    ActionMailer::Base.deliveries.clear
    request_link(unconfirmed.email)
    post redeem_magic_link_path(token: emailed_token)
    expect(response).to redirect_to(root_path)
    expect(unconfirmed.reload).to be_confirmed
  end

  it "limits requests per address" do
    5.times { post magic_links_path, params: {email: user.email} }
    expect(flash[:notice]).to be_present

    post magic_links_path, params: {email: user.email}
    expect(flash[:alert]).to match(/Too many sign-in links/)
  end
end

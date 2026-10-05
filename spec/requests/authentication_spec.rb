require "rails_helper"

RSpec.describe "Authentication", type: :request do
  let(:password) { "correct horse battery" }

  def sign_in_with(email:, password:)
    post user_session_path, params: {user: {email:, password:}}
  end

  it "shows signed-out visitors the landing page, and redirects them from the app's pages to sign in" do
    get root_path
    expect_inertia.to render_component("Pages/Home")
    get setup_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "renders the sign-in page" do
    get new_user_session_path
    expect_inertia.to render_component("Auth/SignIn")
  end

  describe "sign up and confirmation" do
    let(:params) do
      {user: {first_name: "Pat", last_name: "Grower", email: "pat@example.com", password:, password_confirmation: password}}
    end

    it "creates an unconfirmed account and emails a confirmation link" do
      expect { post user_registration_path, params: }.to change(User, :count).by(1)
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:notice]).to match(/confirmation link/i)

      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq(["pat@example.com"])
      token = mail.body.encoded[/confirmation_token=([^"&\s]+)/, 1]

      # Opening the link (as an email link scanner would) doesn't confirm; the button's POST does
      get user_confirmation_path(confirmation_token: token)
      expect_inertia.to render_component("Auth/ConfirmEmail")
      expect(inertia.props).to include(token:, status: "pending")
      expect(User.find_by(email: "pat@example.com")).not_to be_confirmed

      post confirm_user_confirmation_path, params: {confirmation_token: token}
      expect(response).to redirect_to(new_user_session_path)
      expect(User.find_by(email: "pat@example.com")).to be_confirmed

      sign_in_with(email: "pat@example.com", password:)
      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect_inertia.to render_component("Dashboard/Show")
    end

    it "sends validation errors back to the form" do
      post user_registration_path, params: {user: params[:user].merge(password_confirmation: "nope")}
      expect(response).to redirect_to(new_user_registration_path)
      follow_redirect!
      expect(inertia.props[:errors]).to include("password_confirmation")
    end

    it "explains an invalid confirmation link" do
      get user_confirmation_path(confirmation_token: "bogus")
      expect(inertia.props[:status]).to eq("invalid")

      post confirm_user_confirmation_path, params: {confirmation_token: "bogus"}
      expect(response).to redirect_to(new_user_confirmation_path)
      expect(flash[:alert]).to match(/invalid/)
    end

    it "tells someone using a link a second time that they can sign in" do
      user = create(:user, :unconfirmed)
      token = user.confirmation_token
      user.confirm

      get user_confirmation_path(confirmation_token: token)
      expect(inertia.props[:status]).to eq("confirmed")

      post confirm_user_confirmation_path, params: {confirmation_token: token}
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:notice]).to match(/already confirmed/)
    end
  end

  describe "password sign-in" do
    let!(:user) { create(:user, password:) }

    it "signs in and out" do
      sign_in_with(email: user.email, password:)
      expect(response).to redirect_to(root_path)

      delete destroy_user_session_path
      expect(response).to have_http_status(:see_other)
      get root_path
      expect_inertia.to render_component("Pages/Home")
    end

    it "rejects a wrong password without saying whether the account exists" do
      sign_in_with(email: user.email, password: "wrong")
      wrong_password = flash[:alert]
      sign_in_with(email: "nobody@example.com", password: "wrong")
      expect(flash[:alert]).to eq(wrong_password)
    end

    it "does not sign in an unconfirmed account" do
      unconfirmed = create(:user, :unconfirmed, password:)
      sign_in_with(email: unconfirmed.email, password:)
      expect(flash[:alert]).to match(/confirm your email/i)
      get setup_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects Inertia (XHR) requests to sign in instead of returning a bare 401" do
      get setup_path, headers: {"X-Inertia" => "true", "X-Requested-With" => "XMLHttpRequest"}
      expect(response).to have_http_status(:found).or have_http_status(:conflict)
    end
  end

  describe "password reset" do
    let!(:user) { create(:user, password:) }

    it "gives the same response for known and unknown addresses" do
      post user_password_path, params: {user: {email: user.email}}
      known = [response.location, flash[:notice]]
      post user_password_path, params: {user: {email: "nobody@example.com"}}
      expect([response.location, flash[:notice]]).to eq(known)
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it "resets the password from the emailed link" do
      post user_password_path, params: {user: {email: user.email}}
      token = ActionMailer::Base.deliveries.last.body.encoded[/reset_password_token=([^"&\s]+)/, 1]

      get edit_user_password_path(reset_password_token: token)
      expect_inertia.to render_component("Auth/ResetPassword")

      patch user_password_path, params: {user: {reset_password_token: token, password: "a brand new one", password_confirmation: "a brand new one"}}
      expect(response).to redirect_to(root_path)
      expect(user.reload.valid_password?("a brand new one")).to be(true)
    end

    it "sends a bad token back to the form with an error" do
      patch user_password_path, params: {user: {reset_password_token: "bogus", password: "a brand new one", password_confirmation: "a brand new one"}}
      expect(response).to redirect_to(edit_user_password_path(reset_password_token: "bogus"))
      follow_redirect!
      expect(inertia.props[:errors]).to include("reset_password_token")
    end
  end
end

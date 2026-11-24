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

  describe "sign up and confirmation" do
    let(:params) do
      {user: {first_name: "Pat", last_name: "Grower", email: "pat@example.com", password:, password_confirmation: password}}
    end

    # Loads the sign-up page and returns its bot-check token, after the seconds a person takes to fill it in
    def form_token
      get new_user_registration_path
      inertia.props[:form_token].tap { travel SignUpGuard::MIN_SECONDS + 1 }
    end

    it "creates an unconfirmed account and emails a confirmation link" do
      expect { post user_registration_path, params: params.merge(form_token:) }.to change(User, :count).by(1)
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:notice]).to match(/link to confirm your address/i)

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

    it "sends validation errors back to the form, keeping its token's clock" do
      token = form_token
      post user_registration_path, params: {form_token: token, user: params[:user].merge(password_confirmation: "nope")}
      expect(response).to redirect_to(new_user_registration_path)
      follow_redirect!
      expect(inertia.props[:errors]).to include("password_confirmation")
      expect(inertia.props[:form_token]).to eq(token)

      # Corrected at once: still counted from when the form was first shown
      expect { post user_registration_path, params: params.merge(form_token: token) }.to change(User, :count).by(1)
    end

    it "rejects addresses on the blocklist" do
      expect { post user_registration_path, params: {form_token:, user: params[:user].merge(email: "pat@postpro.fun")} }
        .not_to change(User, :count)
      follow_redirect!
      expect(inertia.props[:errors]).to include("email")
    end

    it "tells a bot that fills in the hidden field it signed up, creating nothing" do
      expect { post user_registration_path, params: params.merge(form_token:, website: "https://spam.example") }
        .not_to change(User, :count)
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:notice]).to match(/link to confirm your address/i)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "turns away a sign-up sent sooner than a person could fill in the form" do
      get new_user_registration_path
      token = inertia.props[:form_token]
      expect { post user_registration_path, params: params.merge(form_token: token) }.not_to change(User, :count)
      expect(flash[:notice]).to match(/link to confirm your address/i)
    end

    it "asks for the form again without a valid token" do
      expect { post user_registration_path, params: }.not_to change(User, :count)
      expect(response).to redirect_to(new_user_registration_path)
      expect(flash[:alert]).to match(/fill it in again/)

      token = form_token
      travel SignUpGuard::TOKEN_TTL
      expect { post user_registration_path, params: params.merge(form_token: token) }.not_to change(User, :count)
      expect(flash[:alert]).to match(/fill it in again/)
    end

    it "expires confirmation links after Devise's confirm_within" do
      user = create(:user, :unconfirmed)
      travel 4.days
      post confirm_user_confirmation_path, params: {confirmation_token: user.confirmation_token}
      expect(flash[:alert]).to match(/didn't work/)
      expect(user.reload).not_to be_confirmed
    end

    it "limits confirmation resends to one address" do
      create(:user, :unconfirmed, email: "pat@example.com")
      ActionMailer::Base.deliveries.clear
      LimitsEmailsPerAddress::EMAILS_PER_ADDRESS.times do |i|
        post user_confirmation_path, params: {user: {email: "Pat@example.com"}}, env: {"REMOTE_ADDR" => "203.0.113.#{i}", "HTTP_USER_AGENT" => "Mozilla/5.0"}
        expect(response).to redirect_to(new_user_session_path)
      end
      post user_confirmation_path, params: {user: {email: "pat@example.com"}}, env: {"REMOTE_ADDR" => "203.0.113.99", "HTTP_USER_AGENT" => "Mozilla/5.0"}
      expect(response).to redirect_to(new_user_confirmation_path)
      expect(flash[:alert]).to match(/several emails/)
      expect(ActionMailer::Base.deliveries.size).to eq(LimitsEmailsPerAddress::EMAILS_PER_ADDRESS)
    end

    it "explains an invalid confirmation link" do
      get user_confirmation_path(confirmation_token: "bogus")
      expect(inertia.props[:status]).to eq("invalid")

      post confirm_user_confirmation_path, params: {confirmation_token: "bogus"}
      expect(response).to redirect_to(new_user_confirmation_path)
      expect(flash[:alert]).to match(/didn't work/)
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

    it "clears the pages kept in the browser's history on signing out" do
      sign_in_with(email: user.email, password:)
      delete destroy_user_session_path
      follow_redirect!
      expect_inertia.to render_component("Pages/Home")
      expect(response.body).to include('"clearHistory":true')

      get root_path # only the page after signing out
      expect(response.body).not_to include("clearHistory")
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

    it "answers a save from a page whose session has ended with a 401, which leaves the page and what's typed in place" do
      inertia = {"X-Inertia" => "true", "X-Requested-With" => "XMLHttpRequest", "ACCEPT" => "text/html, application/xhtml+xml"}
      sign_in_with(email: user.email, password:)
      travel 31.hours do
        patch daily_entry_path, params: {date: "2026-07-01"}, headers: inertia
        expect(response).to have_http_status(:unauthorized)
        expect(response.headers["WWW-Authenticate"]).to be_nil # no browser password prompt
        delete farm_path(1), headers: inertia
        expect(response).to have_http_status(:unauthorized)

        get daily_entry_path, headers: inertia # a page is still sent to sign in
        expect(response).to redirect_to(new_user_session_path)
        patch daily_entry_path, params: {date: "2026-07-01"} # as is a plain form
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    it "redirects Inertia (XHR) requests to sign in instead of returning a bare 401" do
      get setup_path, headers: {"X-Inertia" => "true", "X-Requested-With" => "XMLHttpRequest"}
      expect(response).to redirect_to(new_user_session_path)
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

    it "limits reset emails to one address, whether or not it has an account" do
      [user.email, "nobody@example.com"].each do |email|
        LimitsEmailsPerAddress::EMAILS_PER_ADDRESS.times do |i|
          post user_password_path, params: {user: {email:}}, env: {"REMOTE_ADDR" => "203.0.113.#{i}", "HTTP_USER_AGENT" => "Mozilla/5.0"}
          expect(response).to redirect_to(new_user_session_path)
        end
        post user_password_path, params: {user: {email:}}, env: {"REMOTE_ADDR" => "203.0.113.99", "HTTP_USER_AGENT" => "Mozilla/5.0"}
        expect(response).to redirect_to(new_user_password_path)
        expect(flash[:alert]).to match(/several emails/)
      end
      expect(ActionMailer::Base.deliveries.size).to eq(LimitsEmailsPerAddress::EMAILS_PER_ADDRESS)
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

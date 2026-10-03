require "rails_helper"

RSpec.describe "Sign-in links and codes", type: :request do
  let!(:user) { create(:user) }

  def request_email(email = user.email)
    perform_enqueued_jobs { post magic_links_path, params: {email:} }
  end

  def last_mail = ActionMailer::Base.deliveries.last

  def emailed_token
    last_mail.html_part.body.decoded[%r{/account/sign_in_link/([^"\s]+)}, 1]
  end

  def emailed_code
    last_mail.subject[/\d{6}/]
  end

  def wrong_code
    emailed_code.succ.rjust(6, "0")[-6..]
  end

  describe "requesting" do
    it "emails a link and a code, then shows the code form" do
      request_email
      expect(response).to redirect_to(sign_in_code_path)
      expect(last_mail.to).to eq([user.email])
      expect(emailed_code).to match(/\A\d{6}\z/)
      expect(last_mail.text_part.body.decoded).to include(emailed_code)

      follow_redirect!
      expect_inertia.to render_component("Auth/SignInCode")
      expect(inertia.props).to include(email: user.email, ttl_minutes: 15, resend_in: 60)
    end

    it "marks email links so SES doesn't rewrite them for click tracking" do
      request_email
      expect(last_mail.html_part.body.decoded).to include("<a ses:no-track href=")
    end

    it "gives the same response for unknown addresses and sends nothing" do
      request_email("nobody@example.com")
      expect(response).to redirect_to(sign_in_code_path)
      follow_redirect!
      expect(inertia.props[:email]).to eq("nobody@example.com")
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "matches the address case-insensitively" do
      request_email(user.email.upcase)
      expect(last_mail.to).to eq([user.email])
    end

    it "requires an email address" do
      post magic_links_path, params: {email: ""}
      follow_redirect!
      expect(inertia.props[:errors]).to include("email")
    end

    it "sends the code form back to sign-in when nothing was requested" do
      get sign_in_code_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "waits a minute before sending another email" do
      request_email
      request_email
      expect(ActionMailer::Base.deliveries.size).to eq(1)

      travel 61.seconds do
        request_email
        expect(ActionMailer::Base.deliveries.size).to eq(2)
        expect(flash[:notice]).to match(/new code/)
      end
    end

    it "keeps the wait across browsers" do
      request_email
      reset!
      request_email
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it "limits requests per address, saying when to try again" do
      start = Time.zone.parse("2026-10-03 13:20")
      5.times { |i| travel_to(start + i.minutes) { request_email } }
      travel_to(start + 5.minutes) { request_email }
      expect(flash[:alert]).to eq("Too many sign-in emails requested. Please try again in 35 minutes.")
    end

    it "lifts the per-address limit when the user signs in" do
      5.times { |i| travel(i.minutes) { request_email } }
      sign_in user
      get root_path
      delete destroy_user_session_path

      travel(5.minutes) { request_email }
      expect(response).to redirect_to(sign_in_code_path)
      expect(ActionMailer::Base.deliveries.size).to eq(6)
    end

    it "sends a new code straight away after signing in with one" do
      request_email
      post sign_in_code_path, params: {code: emailed_code}
      delete destroy_user_session_path

      request_email
      expect(ActionMailer::Base.deliveries.size).to eq(2)
    end

    it "sends a new code straight away after signing in with a password" do
      request_email
      reset!
      post user_session_path, params: {user: {email: user.email, password: user.password}}
      delete destroy_user_session_path

      request_email
      expect(ActionMailer::Base.deliveries.size).to eq(2)
    end
  end

  describe "the link" do
    it "signs in" do
      request_email
      post redeem_magic_link_path(token: emailed_token)
      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect_inertia.to render_component("Dashboard/Show")
    end

    it "does not sign in on GET, so link scanners can't use it up" do
      request_email
      get magic_link_path(token: emailed_token)
      expect_inertia.to render_component("Auth/MagicLink")
      expect(inertia.props[:valid]).to be(true)

      get root_path
      expect(response).to redirect_to(new_user_session_path)

      post redeem_magic_link_path(token: emailed_token)
      expect(response).to redirect_to(root_path)
    end

    it "works only once" do
      request_email
      token = emailed_token
      post redeem_magic_link_path(token:)
      delete destroy_user_session_path

      post redeem_magic_link_path(token:)
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to match(/expired or was already used/)
    end

    it "expires after 15 minutes" do
      request_email
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
      request_email(unconfirmed.email)
      post redeem_magic_link_path(token: emailed_token)
      expect(response).to redirect_to(root_path)
      expect(unconfirmed.reload).to be_confirmed
    end
  end

  describe "the code" do
    it "signs in, ignoring spaces" do
      request_email
      post sign_in_code_path, params: {code: emailed_code.insert(3, " ")}
      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect_inertia.to render_component("Dashboard/Show")
    end

    it "rejects a wrong code" do
      request_email
      post sign_in_code_path, params: {code: wrong_code}
      expect(response).to redirect_to(sign_in_code_path)
      follow_redirect!
      expect(inertia.props[:errors]).to include("code")
    end

    it "limits tries per IP" do
      request_email
      20.times { post sign_in_code_path, params: {code: wrong_code} }
      post sign_in_code_path, params: {code: emailed_code}
      expect(flash[:alert]).to match(/Too many sign-in attempts. Please try again in \d+ minutes?\./)
    end

    it "stops working after 5 wrong tries" do
      request_email
      code = emailed_code
      5.times { post sign_in_code_path, params: {code: wrong_code} }
      post sign_in_code_path, params: {code:}
      expect(response).to redirect_to(sign_in_code_path)
    end

    it "works only once, and signing in with the link spends it too" do
      request_email
      code = emailed_code
      post redeem_magic_link_path(token: emailed_token)
      delete destroy_user_session_path

      post magic_links_path, params: {email: user.email} # puts the address back in the session
      post sign_in_code_path, params: {code:}
      expect(response).to redirect_to(sign_in_code_path)
    end

    it "only checks the address this browser asked about" do
      other = create(:user)
      request_email(other.email)
      code = emailed_code
      reset!

      request_email(user.email)
      post sign_in_code_path, params: {code:}
      expect(response).to redirect_to(sign_in_code_path)
    end

    it "expires after 15 minutes" do
      request_email
      code = emailed_code
      travel 16.minutes do
        post sign_in_code_path, params: {code:}
        expect(response).to redirect_to(sign_in_code_path)
      end
    end

    it "is replaced by a newer one" do
      request_email
      old_code = emailed_code
      travel 61.seconds do
        request_email
        post sign_in_code_path, params: {code: old_code} unless old_code == emailed_code
        expect(response).to redirect_to(sign_in_code_path)
      end
    end

    it "confirms an unconfirmed account" do
      unconfirmed = create(:user, :unconfirmed)
      ActionMailer::Base.deliveries.clear
      request_email(unconfirmed.email)
      post sign_in_code_path, params: {code: emailed_code}
      expect(unconfirmed.reload).to be_confirmed
    end
  end
end

require "rails_helper"

RSpec.describe "Daily digest", type: :request do
  let(:user) { create(:user, digest_frequency: "daily") }
  let(:group) { user.groups.first }

  describe "the alerts page" do
    let(:home) { create(:farm, group:, name: "Home") }
    let(:river) { create(:farm, group:, name: "River") }
    let!(:north) { create(:field, pivot: create(:pivot, farm: home), name: "North") }
    let!(:south) { create(:field, pivot: north.pivot, name: "South") }
    let!(:east) { create(:field, pivot: create(:pivot, farm: river), name: "East") }

    before { sign_in user }

    it "lists every field by operation and farm, all included by default" do
      get alerts_path
      expect_inertia.to render_component("Alerts/Show")
      expect(inertia.props).to include(frequency: "daily", field_ids: contain_exactly(north.id, south.id, east.id), test_wait: 0)
      expect(inertia.props[:groups].sole[:farms].map { |farm| [farm[:name], farm[:fields].map { |field| field[:name] }] })
        .to eq([["Home", ["North", "South"]], ["River", ["East"]]])
      # The preview is built only when asked for
      expect(inertia.props).not_to have_key(:preview)
    end

    it "leaves out a farm with none of its fields picked, so its new fields stay out" do
      patch alerts_path, params: {digest: {frequency: "needed", field_ids: ["", north.id.to_s]}}
      expect(response).to redirect_to(alerts_path)
      expect(user.reload.digest_frequency).to eq("needed")
      expect(user.digest_exclusions.map(&:subject)).to contain_exactly(south, river)

      later = create(:field, pivot: east.pivot)
      newer = create(:field, pivot: north.pivot)
      # River was left out whole; Home only lost South, so it takes in new fields
      expect(user.digest_fields).to contain_exactly(north, newer)
      expect(user.digest_fields).not_to include(later)
    end

    it "turns the digest off, and leaves out a whole operation" do
      patch alerts_path, params: {digest: {frequency: "never", field_ids: [""]}}
      expect(user.reload.digest_frequency).to eq("never")
      expect(user.digest_exclusions.map(&:subject)).to eq([group])
    end

    it "rejects an unknown frequency without changing the fields" do
      patch alerts_path, params: {digest: {frequency: "hourly", field_ids: [""]}}
      expect(response).to redirect_to(alerts_path)
      follow_redirect!
      expect(inertia.props[:errors]).to include("digest_frequency")
      expect(user.reload.digest_frequency).to eq("daily")
      expect(user.digest_exclusions).to be_empty
    end

    it "ignores fields from other operations" do
      theirs = create(:field, pivot: create(:pivot, farm: create(:farm)))
      patch alerts_path, params: {digest: {frequency: "daily", field_ids: ["", theirs.id.to_s]}}
      expect(user.digest_fields).to be_empty
      expect(user.digest_exclusions.map(&:subject)).to eq([group])
    end

    it "is in the main nav, not on the settings page" do
      get settings_path
      expect(inertia.props).not_to have_key(:digest)
    end
  end

  describe "previewing and testing on the alerts page" do
    let(:pivot) { create(:pivot, farm: create(:farm, group:)) }

    around { |example| travel_to(digest_today) { example.run } }

    before do
      digest_weather(pivot)
      sign_in user
    end

    def preview
      get alerts_path, headers: {"X-Inertia" => "true", "X-Inertia-Partial-Component" => "Alerts/Show",
                                 "X-Inertia-Partial-Data" => "preview", "X-Inertia-Version" => ViteRuby.digest}
      response.parsed_body.dig("props", "preview")
    end

    it "shows today's email, and why it wouldn't be sent" do
      digest_field(pivot, "North", 15)
      expect(preview).to include("skip_reason" => nil, "subject" => "WISP: 1 field OK (Mon, Jul 20)")

      user.update!(digest_frequency: "needed")
      expect(preview).to include("skip_reason" => "No field needs irrigation in the next 3 days.")
      expect(preview["html"]).to include("North")
    end

    it "sends a test email, then waits five minutes before another" do
      digest_field(pivot, "North", 12)
      user.update!(digest_frequency: "never")

      expect { perform_enqueued_jobs { post test_email_alerts_path } }.to change { ActionMailer::Base.deliveries.size }.by(1)
      expect(response).to redirect_to(alerts_path)
      expect(flash[:notice]).to eq("Test email sent to #{user.email}")
      mail = ActionMailer::Base.deliveries.last
      expect(mail.subject).to eq("[Test] WISP: 1 field to watch (Mon, Jul 20)")
      expect(mail.text_part.body.decoded).to include("This is a test you sent from WISP's Alerts page.")

      travel 2.minutes
      expect { perform_enqueued_jobs { post test_email_alerts_path } }.not_to change { ActionMailer::Base.deliveries.size }
      expect(flash[:alert]).to eq("You can send another test email in 3 minutes.")
      get alerts_path
      expect(inertia.props[:test_wait]).to eq(180)

      travel 3.minutes
      expect { perform_enqueued_jobs { post test_email_alerts_path } }.to change { ActionMailer::Base.deliveries.size }.by(1)
    end

    it "doesn't send, or start the cooldown, with nothing in season" do
      expect { post test_email_alerts_path }.not_to have_enqueued_mail(DigestMailer)
      expect(flash[:alert]).to eq("There's nothing to send: no included field has a crop in season today.")
      expect(user.reload.digest_test_sent_at).to be_nil
    end
  end

  describe "unsubscribing" do
    let(:token) { user.generate_token_for(:digest_unsubscribe) }

    it "asks first, then turns the digest off without signing in" do
      get digest_unsubscribe_path(token:)
      expect_inertia.to render_component("Auth/Unsubscribe")
      expect(inertia.props).to include(valid: true, done: false)
      expect(user.reload.digest_frequency).to eq("daily")

      post digest_unsubscribe_path(token:)
      expect(inertia.props).to include(valid: true, done: true)
      expect(user.reload.digest_frequency).to eq("never")
    end

    it "takes a mail provider's one-click POST without a CSRF token" do
      ActionController::Base.allow_forgery_protection = true
      post digest_unsubscribe_path(token:), params: {"List-Unsubscribe" => "One-Click"}
      expect(response).to have_http_status(:ok)
      expect(user.reload.digest_frequency).to eq("never")
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it "rejects a made-up token" do
      post digest_unsubscribe_path(token: "nope")
      expect(inertia.props).to include(valid: false)
      expect(user.reload.digest_frequency).to eq("daily")
    end
  end

  describe "links from the email" do
    it "switch to the field's operation, if the user belongs to it" do
      other_group = create(:group, name: "Partners")
      create(:membership, user:, group: other_group)
      field = create(:field, pivot: create(:pivot, farm: create(:farm, group: other_group)))
      sign_in user
      get root_path
      expect(inertia.props[:auth][:group][:id]).to eq(group.id)

      get field_path(field, operation: other_group.id)
      expect(response).to have_http_status(:ok)
      expect(inertia.props[:auth][:group][:id]).to eq(other_group.id)

      outsiders = create(:user).groups.first
      get root_path(operation: outsiders.id)
      expect(inertia.props[:auth][:group][:id]).to eq(other_group.id)
    end
  end

  describe "the admin preview" do
    let(:admin) { create(:user, admin: true) }
    let(:pivot) { create(:pivot, farm: create(:farm, group:)) }

    around { |example| travel_to(digest_today) { example.run } }

    it "shows what would be sent today, without sending it" do
      digest_weather(pivot)
      digest_field(pivot, "North", 12)
      sign_in admin
      expect { get digest_admin_user_path(user) }.not_to change { ActionMailer::Base.deliveries.size }
      expect_inertia.to render_component("Admin/Users/Digest")
      expect(inertia.props[:preview]).to include(skip_reason: nil, subject: "WISP: 1 field to watch (Mon, Jul 20)")
      expect(inertia.props[:preview][:html]).to include("Irrigate by Wed, Jul 22")
    end

    it "says why nothing would be sent" do
      sign_in admin
      get digest_admin_user_path(user)
      expect(inertia.props[:preview]).to include(skip_reason: "No included field has a crop in season today.", html: nil)
    end

    it "is hidden from users who aren't admins" do
      sign_in user
      get root_path
      get digest_admin_user_path(admin)
      expect(response).to have_http_status(:not_found)
    end
  end
end

require "rails_helper"

RSpec.describe "Daily digest", type: :request do
  let(:user) { create(:user) }
  let(:group) { user.groups.first }

  describe "settings" do
    let(:home) { create(:farm, group:, name: "Home") }
    let(:river) { create(:farm, group:, name: "River") }
    let!(:north) { create(:field, pivot: create(:pivot, farm: home), name: "North") }
    let!(:south) { create(:field, pivot: north.pivot, name: "South") }
    let!(:east) { create(:field, pivot: create(:pivot, farm: river), name: "East") }

    before { sign_in user }

    it "lists every field by operation and farm, all included by default" do
      get settings_path
      digest = inertia.props[:digest]
      expect(digest).to include(enabled: true, field_ids: contain_exactly(north.id, south.id, east.id))
      expect(digest[:groups].sole[:farms].map { |farm| [farm[:name], farm[:fields].map { |field| field[:name] }] })
        .to eq([["Home", ["North", "South"]], ["River", ["East"]]])
    end

    it "leaves out a farm with none of its fields picked, so its new fields stay out" do
      patch digest_settings_path, params: {digest: {enabled: "1", field_ids: ["", north.id.to_s]}}
      expect(response).to redirect_to(settings_path)
      expect(user.digest_exclusions.map(&:subject)).to contain_exactly(south, river)

      later = create(:field, pivot: east.pivot)
      newer = create(:field, pivot: north.pivot)
      # River was left out whole; Home only lost South, so it takes in new fields
      expect(user.digest_fields).to contain_exactly(north, newer)
      expect(user.digest_fields).not_to include(later)
    end

    it "turns the digest off, and leaves out a whole operation" do
      patch digest_settings_path, params: {digest: {enabled: "0", field_ids: [""]}}
      expect(user.reload.digest).to be(false)
      expect(user.digest_exclusions.map(&:subject)).to eq([group])
    end

    it "ignores fields from other operations" do
      theirs = create(:field, pivot: create(:pivot, farm: create(:farm)))
      patch digest_settings_path, params: {digest: {enabled: "1", field_ids: ["", theirs.id.to_s]}}
      expect(user.digest_fields).to be_empty
      expect(user.digest_exclusions.map(&:subject)).to eq([group])
    end
  end

  describe "unsubscribing" do
    let(:token) { user.generate_token_for(:digest_unsubscribe) }

    it "asks first, then turns the digest off without signing in" do
      get digest_unsubscribe_path(token:)
      expect_inertia.to render_component("Auth/Unsubscribe")
      expect(inertia.props).to include(valid: true, done: false)
      expect(user.reload.digest).to be(true)

      post digest_unsubscribe_path(token:)
      expect(inertia.props).to include(valid: true, done: true)
      expect(user.reload.digest).to be(false)
    end

    it "takes a mail provider's one-click POST without a CSRF token" do
      ActionController::Base.allow_forgery_protection = true
      post digest_unsubscribe_path(token:), params: {"List-Unsubscribe" => "One-Click"}
      expect(response).to have_http_status(:ok)
      expect(user.reload.digest).to be(false)
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it "rejects a made-up token" do
      post digest_unsubscribe_path(token: "nope")
      expect(inertia.props).to include(valid: false)
      expect(user.reload.digest).to be(true)
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
      expect(inertia.props).to include(skip_reason: nil, subject: "WISP: 1 field to watch (Mon, Jul 20)")
      expect(inertia.props[:html]).to include("Irrigate by Wed, Jul 22")
    end

    it "says why nothing would be sent" do
      sign_in admin
      get digest_admin_user_path(user)
      expect(inertia.props).to include(skip_reason: "No included field has a crop in season today.", html: nil)
    end

    it "is hidden from users who aren't admins" do
      sign_in user
      get root_path
      get digest_admin_user_path(admin)
      expect(response).to have_http_status(:not_found)
    end
  end
end

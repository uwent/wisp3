require "rails_helper"

RSpec.describe "Admin announcements", type: :request do
  let(:admin) { create(:user, admin: true, email: "staff@farm.test", first_name: "Sam") }
  let!(:grower) { create(:user, email: "grower@farm.test") }
  let(:params) { {announcement: {subject: "Training on {{first_name|Monday}}", body: "Hi **{{first_name}}**", audience: "all"}} }

  before { sign_in admin }

  it "saves a draft and shows the composer each audience's count" do
    travel_to Time.zone.local(2026, 2, 10, 9)
    get new_admin_announcement_path
    expect_inertia.to render_component("Admin/Announcements/Form")
    expect(inertia.props[:audience_date]).to eq("2025-03-01")
    expect(inertia.props[:audiences].find { |a| a["key"] == "all" }).to include("count" => 2)
    expect(inertia.props[:placeholders].map { |p| p["key"] }).to include("first_name", "email")

    expect { post admin_announcements_path, params: }.to change(Announcement, :count).by(1)
    announcement = Announcement.last
    expect(response).to redirect_to(admin_announcement_path(announcement))
    expect(announcement).to have_attributes(status: "draft", created_by: admin)

    get admin_announcement_path(announcement)
    expect_inertia.to render_component("Admin/Announcements/Show")
    expect(inertia.props[:recipients_now]).to eq(2)
    expect(inertia.props[:preview][:subject]).to eq("Training on Sam")
    expect(inertia.props[:preview][:html]).to include("Hi <strong>Sam</strong>")
  end

  it "returns errors for an unknown placeholder" do
    post admin_announcements_path, params: {announcement: params[:announcement].merge(body: "{{nmae}}")}
    expect(response).to redirect_to(new_admin_announcement_path)
    follow_redirect!
    expect(inertia.props[:errors]["body"].sole).to start_with("Message has {{nmae}}")
  end

  it "previews the email being written as JSON" do
    post preview_admin_announcements_path, params: params, as: :json
    expect(response.parsed_body).to include("subject" => "Training on Sam", "errors" => [])
    expect(response.parsed_body["html"]).to include("Hi <strong>Sam</strong>", "Unsubscribe from WISP announcements")
  end

  it "sends a test to the admin alone, then sends to the audience once" do
    announcement = Announcement.create!(params[:announcement])
    expect { post test_admin_announcement_path(announcement) }.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(ActionMailer::Base.deliveries.last).to have_attributes(to: ["staff@farm.test"], subject: "[Test] Training on Sam")
    expect(announcement.reload.status).to eq("draft")

    post deliver_admin_announcement_path(announcement)
    expect(flash[:notice]).to eq("Sending to 2 people")
    expect(announcement.reload.status).to eq("sending")
    expect(AnnouncementJob).to have_been_enqueued.with(announcement)

    # Sent, it can't be changed, deleted or sent again
    patch admin_announcement_path(announcement), params: {announcement: {subject: "Changed"}}
    delete admin_announcement_path(announcement)
    post deliver_admin_announcement_path(announcement)
    expect(announcement.reload).to have_attributes(subject: "Training on {{first_name|Monday}}", recipients_count: 2)
    expect(AnnouncementJob).to have_been_enqueued.once
  end

  it "sends again to those a stopped send missed, but not while it's still sending" do
    announcement = Announcement.create!(params[:announcement])
    post deliver_admin_announcement_path(announcement)
    announcement.deliveries.find_by!(user: grower).update!(status: "failed", error: "SMTP")
    announcement.deliveries.find_by!(user: admin).update!(status: "sent")

    post resume_admin_announcement_path(announcement) # sending, and moved a moment ago
    expect(flash[:alert]).to eq("It's still sending.")
    expect(AnnouncementJob).to have_been_enqueued.once

    announcement.update!(status: "incomplete")
    post resume_admin_announcement_path(announcement)
    expect(flash[:notice]).to eq("Sending again to those it missed")
    expect(announcement.reload.status).to eq("sending")
    expect(announcement.deliveries.order(:status).pluck(:status)).to eq(%w[pending sent]) # never again to those it reached
    expect(AnnouncementJob).to have_been_enqueued.twice
  end

  it "edits and deletes drafts" do
    announcement = Announcement.create!(params[:announcement])
    patch admin_announcement_path(announcement), params: {announcement: {subject: "Changed", audience: "joined_since", audience_date: "2026-01-01"}}
    expect(announcement.reload).to have_attributes(subject: "Changed", audience_text: "Joined since Jan 1, 2026")
    expect { delete admin_announcement_path(announcement) }.to change(Announcement, :count).by(-1)
  end

  it "lists announcements" do
    Announcement.create!(params[:announcement])
    get admin_announcements_path
    expect_inertia.to render_component("Admin/Announcements/Index")
    expect(inertia.props[:announcements].sole).to include(subject: "Training on {{first_name|Monday}}", status: "draft")
  end
end

RSpec.describe "Announcement unsubscribe", type: :request do
  let(:user) { create(:user, digest_frequency: "daily") }
  let(:token) { user.generate_token_for(:announcement_unsubscribe) }

  it "asks first, then turns announcements off without touching the digest" do
    get announcement_unsubscribe_path(token:)
    expect_inertia.to render_component("Auth/Unsubscribe")
    expect(inertia.props).to include(kind: "announcements", valid: true, done: false)

    post announcement_unsubscribe_path(token:)
    expect(inertia.props).to include(valid: true, done: true)
    expect(user.reload).to have_attributes(announcements: false, digest_frequency: "daily")
  end

  it "doesn't take the digest's token" do
    post announcement_unsubscribe_path(token: user.generate_token_for(:digest_unsubscribe))
    expect(inertia.props).to include(valid: false)
    expect(user.reload.announcements).to be(true)
  end

  it "can be turned back on in settings" do
    user.update!(announcements: false)
    sign_in user
    patch settings_path, params: {user: {announcements: "1"}}
    expect(user.reload.announcements).to be(true)
  end
end

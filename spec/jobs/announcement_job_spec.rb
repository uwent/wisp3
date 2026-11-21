require "rails_helper"

RSpec.describe AnnouncementJob do
  let(:admin) { create(:user, email: "staff@farm.test", admin: true) }
  let(:announcement) { Announcement.create!(subject: "Training {{first_name|soon}}", body: "Hi", audience: "all") }
  let!(:ann) { create(:user, email: "ann@farm.test", first_name: "Ann") }
  let!(:bob) { create(:user, email: "bob@farm.test") }

  before { announcement.send!(by: admin) }

  it "sends each recipient one email and marks the announcement sent" do
    expect { described_class.perform_now(announcement, throttle: 0) }.to change { ActionMailer::Base.deliveries.size }.by(3)
    mail = ActionMailer::Base.deliveries.find { |m| m.to == ["ann@farm.test"] }
    expect(mail.subject).to eq("Training Ann")
    expect(mail.reply_to).to eq(["agweather@cals.wisc.edu"])
    expect(mail["List-Unsubscribe"].value).to include("/announcements/unsubscribe?token=")
    expect(announcement.reload.status).to eq("sent")
    expect(announcement.progress).to eq(pending: 0, sent: 3, failed: 0, skipped: 0)

    expect { described_class.perform_now(announcement, throttle: 0) }.not_to change { ActionMailer::Base.deliveries.size }
  end

  it "skips someone who unsubscribed after it started" do
    bob.update!(announcements: false)
    described_class.perform_now(announcement, throttle: 0)
    expect(ActionMailer::Base.deliveries.flat_map(&:to)).not_to include("bob@farm.test")
    expect(announcement.reload.progress).to include(sent: 2, skipped: 1)
    expect(announcement.status).to eq("sent")
  end

  it "keeps going past a failure, ends incomplete, and resumes only the failed" do
    allow(AnnouncementMailer).to receive(:announcement).and_call_original
    allow(AnnouncementMailer).to receive(:announcement).with(announcement, bob).and_raise(Net::SMTPServerBusy, "throttled")

    expect { described_class.perform_now(announcement, throttle: 0) }.to raise_error(AnnouncementJob::Incomplete, /1 of 3/)
    expect(ActionMailer::Base.deliveries.size).to eq(2)
    expect(announcement.reload).to have_attributes(status: "incomplete", resumable?: true)
    expect(announcement.deliveries.find_by(user: bob).error).to include("throttled")

    allow(AnnouncementMailer).to receive(:announcement).with(announcement, bob).and_call_original
    expect(announcement.resume!).to be(true)
    described_class.perform_now(announcement, throttle: 0)
    expect(ActionMailer::Base.deliveries.size).to eq(3)
    expect(announcement.reload.status).to eq("sent")
  end
end

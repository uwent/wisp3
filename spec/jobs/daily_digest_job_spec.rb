require "rails_helper"

RSpec.describe DailyDigestJob do
  let(:user) { create(:user) }
  let(:pivot) { create(:pivot, farm: create(:farm, group: user.groups.first)) }

  before do
    digest_weather(pivot)
    digest_field(pivot, "North", 12)
  end

  around { |example| travel_to(digest_today) { example.run } }

  it "sends each user with the digest on and a field in season one email a day" do
    off = create(:user, digest: false)
    unconfirmed = create(:user, :unconfirmed)
    [off, unconfirmed].each { |other| create(:membership, user: other, group: user.groups.first) }
    create(:user) # no fields

    expect { described_class.perform_now }.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(ActionMailer::Base.deliveries.last.to).to eq([user.email])
    expect(user.reload.digest_sent_on).to eq(Date.new(2026, 7, 20))

    expect { described_class.perform_now }.not_to change { ActionMailer::Base.deliveries.size }
    travel 1.day
    expect { described_class.perform_now }.to change { ActionMailer::Base.deliveries.size }.by(1)
  end

  it "carries on past a user whose digest fails" do
    other = create(:user)
    create(:membership, user: other, group: user.groups.first)
    allow(DigestMailer).to receive(:daily).and_call_original
    allow(DigestMailer).to receive(:daily).with(having_attributes(user:)).and_raise("boom")
    expect(Rails.error).to receive(:report).with(an_instance_of(RuntimeError), context: {user_id: user.id})

    expect { described_class.perform_now }.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(user.reload.digest_sent_on).to be_nil
  end
end

require "rails_helper"

RSpec.describe HealthCheckJob do
  let!(:admins) { [create(:user, admin: true, email: "staff@example.com"), create(:user, admin: true, email: "ops@example.com")] }
  let(:problem) do
    HealthCheck::Problem.new(kind: :failed_jobs, summary: "1 failed job, 1 new in the last 24 h",
      details: [HealthCheck::Detail.new(text: "DailyDigestJob: 1 failed")])
  end

  before { create(:user, :unconfirmed, admin: true) }

  it "emails the confirmed admins once when there are problems" do
    allow_any_instance_of(HealthCheck).to receive(:problems).and_return([problem])
    expect { described_class.perform_now }.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(ActionMailer::Base.deliveries.last.to).to eq(admins.map(&:email).sort)
  end

  it "sends nothing when all is well" do
    allow_any_instance_of(HealthCheck).to receive(:problems).and_return([])
    expect { described_class.perform_now }.not_to change { ActionMailer::Base.deliveries.size }
  end
end

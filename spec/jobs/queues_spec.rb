require "rails_helper"

# Mail has a worker of its own and long jobs go on the bulk queue (config/queue.yml), so a sign-in
# code never waits behind an announcement or the digest
RSpec.describe "Job queues" do
  let(:user) { create(:user) }

  it "puts mail sent later, sign-in links included, on the mailers queue" do
    expect { MagicLinkMailer.sign_in_link(user, "token", "123456").deliver_later }
      .to have_enqueued_job(SecretMailDeliveryJob).on_queue("mailers")
    expect { DigestMailer.test_daily(user).deliver_later }
      .to have_enqueued_job(ActionMailer::MailDeliveryJob).on_queue("mailers")
  end

  it "puts the long mail jobs on the bulk queue and weather on its own" do
    expect(AnnouncementJob.new.queue_name).to eq("bulk")
    expect(DailyDigestJob.new.queue_name).to eq("bulk")
    expect(WeatherRefreshJob.new.queue_name).to eq("weather")
    expect(HealthCheckJob.new.queue_name).to eq("default")
  end

  it "has a worker for the mailers queue alone, beside one for every queue" do
    workers = YAML.load(ERB.new(Rails.root.join("config/queue.yml").read).result, aliases: true)
      .dig("production", "workers")
    expect(workers.map { |worker| worker["queues"] }).to contain_exactly("mailers", "*")
  end
end

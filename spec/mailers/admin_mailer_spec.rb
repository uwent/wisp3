require "rails_helper"

RSpec.describe AdminMailer do
  it "lists the health check's problems, linking the weather page" do
    problems = [
      HealthCheck::Problem.new(kind: :missing_weather, summary: "1 weather cell missing weather",
        details: ["Cell 4 (44.1200, -89.5300): no forecast"]),
      HealthCheck::Problem.new(kind: :failed_jobs, summary: "2 jobs failed since the last check",
        details: ["DailyDigestJob: 2 failed, latest 3 h ago: DailyDigestJob::Incomplete: 1 of 9 daily emails failed"])
    ]

    mail = described_class.health(problems, to: ["staff@example.com"], now: Time.zone.local(2026, 7, 20, 7))
    expect(mail.to).to eq(["staff@example.com"])
    expect(mail.subject).to eq("WISP health check: 2 problems (Mon, Jul 20)")

    html = mail.html_part.body.decoded
    expect(html).to include("<h1", "<h2", "1 weather cell missing weather", "Cell 4 (44.1200, -89.5300): no forecast")
    expect(Nokogiri::HTML(html).at_css("a[href='http://example.com/admin/weather']").text).to eq("Weather status")
    expect(html).to include(%(<html lang="en">))

    text = mail.text_part.body.decoded
    expect(text).to include("2 JOBS FAILED SINCE THE LAST CHECK", "- DailyDigestJob: 2 failed",
      "Weather status: http://example.com/admin/weather")
  end
end

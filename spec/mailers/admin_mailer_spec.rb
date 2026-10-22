require "rails_helper"

RSpec.describe AdminMailer do
  it "lists the health check's problems, linking the weather page and the users" do
    user = create(:user, email: "jane@example.com")
    problems = [
      HealthCheck::Problem.new(kind: :stale_weather, summary: "1 weather cell stale or failing",
        details: [HealthCheck::Detail.new(text: "Cell 4 (44.1200, -89.5300): no forecast")]),
      HealthCheck::Problem.new(kind: :digest_not_sent, summary: "1 user didn't get today's daily email",
        details: [HealthCheck::Detail.new(text: user.email, user_id: user.id)])
    ]

    mail = described_class.health(problems, to: ["staff@example.com"], now: Time.zone.local(2026, 7, 20, 7))
    expect(mail.to).to eq(["staff@example.com"])
    expect(mail.subject).to eq("WISP health check: 2 problems (Mon, Jul 20)")

    html = mail.html_part.body.decoded
    expect(html).to include("<h1", "<h2", "1 weather cell stale or failing", "Cell 4 (44.1200, -89.5300): no forecast")
    expect(html).to include(%(<a ses:no-track href="http://example.com/admin/weather">Weather status</a>))
    expect(html).to include(%(<a ses:no-track href="http://example.com/admin/users/#{user.id}">jane@example.com</a>))
    expect(html).to include(%(<html lang="en">))

    text = mail.text_part.body.decoded
    expect(text).to include("1 USER DIDN'T GET TODAY'S DAILY EMAIL", "- jane@example.com (http://example.com/admin/users/#{user.id})",
      "Weather status: http://example.com/admin/weather")
  end
end

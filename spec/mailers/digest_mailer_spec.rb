require "rails_helper"

RSpec.describe DigestMailer do
  let(:user) { create(:user, email: "pat@example.com", digest_frequency: "daily") }
  let(:pivot) { create(:pivot, farm: create(:farm, group: user.groups.first, name: "Home"), name: "Pivot 1") }

  before { digest_weather(pivot) }

  around { |example| travel_to(digest_today) { example.run } }

  it "lists fields needing attention first, then every field by farm and pivot with the pivot's weather" do
    soon = digest_field(pivot, "Soon", 12)
    digest_field(pivot, "Fine", 15)

    mail = described_class.daily(DailyDigest.new(user))
    expect(mail.to).to eq(["pat@example.com"])
    expect(mail.subject).to eq("WISP: 1 field to watch (Mon, Jul 20)")

    text = mail.text_part.body.decoded
    expect(text).to include("NEEDS ATTENTION\n\n- Soon [! Caution] Home › Pivot 1: Irrigate by Wed, Jul 22\n")
    expect(text).to include("== HOME ==\n\nPivot 1\n" \
      "  Past 7 days: 0.00 in rain · 1.40 in ET · highs 85°F, lows 60°F\n" \
      "  Next 7 days: 0.00 in rain · 1.40 in ET · highs 88°F, lows 62°F\n")
    expect(text).to include("  Fine [✓ OK] Potato · AD 1.00 in\n  Irrigate by Sat, Jul 25\n")
    expect(text).to include("  Soon [! Caution] Potato · AD 0.28 in of 1.20 in · 11.2% moisture\n  Irrigate by Wed, Jul 22. Projected")
    expect(text).to include("Last rain: None · Last irrigation: None")
    # In the tree, fields are in name order
    expect(text.index("  Fine")).to be < text.index("  Soon")
    expect(text).to include("You get this email from WISP each morning while your fields are in season.")

    html = mail.html_part.body.decoded
    expect(html).to include("ses:no-track")
    expect(html).to include("http://example.com/fields/#{soon.id}?operation=#{user.groups.first.id}")
    expect(html).to include("http://example.com/pivots/#{pivot.id}?operation=#{user.groups.first.id}")
    expect(html).to include("http://example.com/alerts")
  end

  it "names the operation when the fields come from several" do
    digest_field(pivot, "Fine", 15)
    partners = create(:group, name: "Partners")
    create(:membership, user:, group: partners)
    digest_field(create(:pivot, farm: create(:farm, group: partners, name: "Far"), weather_cell: pivot.weather_cell), "Away", 15)
    text = described_class.daily(DailyDigest.new(user)).text_part.body.decoded
    expect(text).to include("== FAR · PARTNERS ==")
    expect(text).to include("== HOME · #{user.groups.first.name.upcase} ==")
  end

  it "marks a test email, and says how often the real one comes" do
    digest_field(pivot, "Soon", 12)
    user.update!(digest_frequency: "needed")
    mail = described_class.test_daily(user)
    expect(mail.subject).to eq("[Test] WISP: 1 field to watch (Mon, Jul 20)")
    expect(mail.text_part.body.decoded).to include("This is a test you sent from WISP's Alerts page. You get this " \
      "email from WISP on mornings when a field needs irrigation within 3 days.")
  end

  it "has an unsubscribe link and one-click List-Unsubscribe headers" do
    digest_field(pivot, "Fine", 15)
    mail = described_class.daily(DailyDigest.new(user))
    url = mail.header["List-Unsubscribe"].value[/<(.+)>/, 1]
    token = url[%r{/digest/unsubscribe/(.+)\z}, 1]
    expect(User.find_by_token_for(:digest_unsubscribe, token)).to eq(user)
    expect(mail.header["List-Unsubscribe-Post"].value).to eq("List-Unsubscribe=One-Click")
    expect(mail.text_part.body.decoded).to include("Unsubscribe: #{url}")
  end

  it "uses the reader's units" do
    user.update!(unit_system: "metric")
    digest_field(pivot, "Fine", 15)
    expect(described_class.daily(DailyDigest.new(user)).text_part.body.decoded).to include("AD 25.4 mm")
  end
end

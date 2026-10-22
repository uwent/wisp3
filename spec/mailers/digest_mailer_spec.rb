require "rails_helper"

RSpec.describe DigestMailer do
  let(:user) { create(:user, email: "pat@example.com", digest_frequency: "daily") }
  let(:pivot) { create(:pivot, farm: create(:farm, group: user.groups.first, name: "Home"), name: "Pivot 1") }

  before { digest_weather(pivot) }

  around { |example| travel_to(digest_today) { example.run } }

  it "lists fields needing attention first, then every field by weather zone and pivot, with one operation and farm on a line" do
    soon = digest_field(pivot, "Soon", 12)
    digest_field(pivot, "Fine", 15)

    mail = described_class.daily(DailyDigest.new(user))
    expect(mail.to).to eq(["pat@example.com"])
    expect(mail.subject).to eq("WISP: 1 field to watch (Mon, Jul 20)")

    text = mail.text_part.body.decoded
    expect(text).to include("NEEDS ATTENTION\n\n- Field: Soon [! Caution] Home › Pivot 1: Irrigate by Wed, Jul 22\n")
    cell = pivot.weather_cell
    zone = format("Weather zone 1 (%.2f°N, %.2f°W)", cell.latitude, -cell.longitude)
    expect(text).to start_with("Your fields this morning, Monday, July 20\nOperation: #{user.groups.first.name} · Farm: Home\n")
    expect(text).not_to include("OPERATION:", "FARM:")
    expect(text).to include("\n-- #{zone} --\n" \
      "   Past 7 days: 0.00 in rain · 1.40 in ET · highs 85°F, lows 60°F\n" \
      "   Next 7 days: 0.00 in rain · 1.40 in ET · highs 88°F, lows 62°F\n" \
      "   Pivots in this zone: Pivot 1\n\n   Pivot: Pivot 1\n")
    expect(text).to include("This email lists 2 fields on 1 pivot, of the 2 fields on 1 pivot your alerts cover (2 with a crop this season).")
    expect(text).to include("     Field: Fine [✓ OK] Potato · AD 1.00 in\n     Irrigate by Sat, Jul 25\n")
    expect(text).to include("     Field: Soon [! Caution] Potato · AD 0.28 in of 1.20 in · 11.2% moisture\n     Irrigate by Wed, Jul 22. Projected")
    expect(text).to include("Last rain: None · Last irrigation: None")
    # In the tree, fields are in name order
    expect(text.index("Field: Fine")).to be < text.index("     Field: Soon")
    expect(text).to include("You get this email from WISP each morning while your fields are in season.")

    html = mail.html_part.body.decoded
    expect(html).to include("ses:no-track")
    expect(html).to include("http://example.com/fields/#{soon.id}?operation=#{user.groups.first.id}")
    expect(html).to include("http://example.com/pivots/#{pivot.id}?operation=#{user.groups.first.id}")
    expect(html).to include("http://example.com/alerts")
  end

  it "is a document in English titled by its subject, whose headings don't skip a level" do
    digest_field(pivot, "Soon", 12)

    mail = described_class.daily(DailyDigest.new(user))
    html = Nokogiri::HTML(mail.html_part.body.decoded)
    expect(html.at("html")["lang"]).to eq("en")
    expect(html.at("title").text).to eq(mail.subject)
    levels = html.css("h1, h2, h3, h4, h5, h6").map { |heading| heading.name[1].to_i }
    expect(levels.first).to eq(1)
    expect(levels.each_cons(2).map { |a, b| b - a }.max).to be <= 1
  end

  it "lists each field's readings to enter and checks to make" do
    field = digest_field(pivot, "Stale", 15)
    field.field_entries.update_all(date: Date.new(2026, 7, 10))
    field.plantings.sole.canopy_observations.update_all(pct_cover: 40)

    mail = described_class.daily(DailyDigest.new(user))
    todo = "To do: Enter a soil moisture reading (last Jul 10) · Enter a percent cover reading (last Jul 1)"
    expect(mail.text_part.body.decoded).to include("\n     #{todo}\n")
    expect(mail.html_part.body.decoded).to include(todo)
  end

  it "gives each operation its own section, and each its weather zones" do
    digest_field(pivot, "Fine", 15)
    partners = create(:group, name: "Partners")
    create(:membership, user:, group: partners)
    digest_field(create(:pivot, farm: create(:farm, group: partners, name: "Far"), weather_cell: pivot.weather_cell), "Away", 15)
    text = described_class.daily(DailyDigest.new(user)).text_part.body.decoded
    expect(text).to include("=== OPERATION: PARTNERS ===\n\n== FARM: FAR ==")
    expect(text).to include("=== OPERATION: #{user.groups.first.name.upcase} ===\n\n== FARM: HOME ==")
    expect(text.scan("-- Weather zone 1").size).to eq(2)

    # Out of season, under "all the fields it covers"
    user.update!(digest_scope: "all")
    away = Field.find_by!(name: "Away")
    away.plantings.sole.update!(end_date: Date.new(2026, 7, 10))
    text = described_class.daily(DailyDigest.new(user)).text_part.body.decoded
    expect(text).to include("     Field: Away [– Off season] Potato · season ended Jul 10\n")
    html = described_class.daily(DailyDigest.new(user)).html_part.body.decoded
    expect(html).to include("– Off season", "Potato · season ended Jul 10")
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
    token = CGI.unescape(url[%r{/digest/unsubscribe\?token=(.+)\z}, 1])
    expect(User.find_by_token_for(:digest_unsubscribe, token)).to eq(user)
    expect(mail.header["List-Unsubscribe-Post"].value).to eq("List-Unsubscribe=One-Click")
    expect(mail.text_part.body.decoded).to include("Unsubscribe: #{url}")
  end

  it "says when nothing needs doing" do
    digest_field(pivot, "Fine", 15)
    user.update!(digest_scope: "needs_irrigation")
    mail = described_class.daily(DailyDigest.new(user))
    expect(mail.text_part.body.decoded).to include("No action needed. No field needs irrigation now or within 3 days.")
    expect(mail.text_part.body.decoded).to include("Pivots in this zone: Pivot 1")
    expect(mail.text_part.body.decoded).not_to include("Field: Fine")
  end

  it "uses the reader's units" do
    user.update!(unit_system: "metric")
    digest_field(pivot, "Fine", 15)
    expect(described_class.daily(DailyDigest.new(user)).text_part.body.decoded).to include("AD 25.4 mm")
  end
end

require "rails_helper"

RSpec.describe DigestMailer do
  let(:user) { create(:user, email: "pat@example.com") }
  let(:pivot) { create(:pivot, farm: create(:farm, group: user.groups.first, name: "Home"), name: "Pivot 1") }

  before { digest_weather(pivot) }

  around { |example| travel_to(digest_today) { example.run } }

  it "leads with the fields needing attention, then a line for each of the rest" do
    soon = digest_field(pivot, "Soon", 12)
    digest_field(pivot, "Fine", 15)

    mail = described_class.daily(DailyDigest.new(user))
    expect(mail.to).to eq(["pat@example.com"])
    expect(mail.subject).to eq("WISP: 1 field to watch (Mon, Jul 20)")

    text = mail.text_part.body.decoded
    expect(text).to include("NEEDS ATTENTION\n\nSoon [! Caution]\nPotato · Home › Pivot 1\nIrrigate by Wed, Jul 22.")
    expect(text).to include("Last rain: None · Last irrigation: None")
    expect(text).to include("EVERYTHING ELSE\n\n- Fine [✓ OK]: AD 1.00 in. Irrigate by Sat, Jul 25")
    expect(text.index("Soon")).to be < text.index("Fine")

    html = mail.html_part.body.decoded
    expect(html).to include("ses:no-track")
    expect(html).to include("http://example.com/fields/#{soon.id}?operation=#{user.groups.first.id}")
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

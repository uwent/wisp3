require "rails_helper"

RSpec.describe Announcement do
  def grower(email, **attributes) = create(:user, email:, **attributes)

  describe "recipients" do
    let(:today) { Date.new(2026, 7, 20) }

    it "reaches confirmed accounts that haven't unsubscribed, never example addresses" do
      ann = grower("ann@farm.test")
      grower("bob@farm.test", announcements: false)
      create(:user, :unconfirmed, email: "cy@farm.test")
      grower("demo@example.com")
      expect(described_class.recipients_for("all")).to contain_exactly(ann)
    end

    it "picks accounts active or signed in since a date" do
      used = grower("used@farm.test")
      ActivityDay.record(used, date: today, area: "dashboard")
      signed_in = grower("signed@farm.test", current_sign_in_at: today.noon)
      stale = grower("stale@farm.test", current_sign_in_at: (today - 30).noon)
      ActivityDay.record(stale, date: today - 30, area: "dashboard")
      expect(described_class.recipients_for("active_since", today)).to contain_exactly(used, signed_in)
    end

    it "picks accounts created since a date" do
      travel_to(today.noon) { grower("new@farm.test") }
      travel_to((today - 1).noon) { grower("old@farm.test") }
      expect(described_class.recipients_for("joined_since", today).map(&:email)).to eq(["new@farm.test"])
    end

    it "picks accounts none of whose operations has a farm" do
      empty = grower("empty@farm.test")
      farming = grower("farming@farm.test")
      create(:farm, group: farming.groups.first)
      member = grower("member@farm.test")
      create(:membership, user: member, group: farming.groups.first)
      expect(described_class.recipients_for("no_farms")).to contain_exactly(empty)
    end
  end

  describe "#render_for" do
    let(:user) { build(:user, first_name: "Ann", last_name: "<Lee>", email: "ann@farm.test") }

    it "fills placeholders, with fallbacks, in the subject, the HTML (escaped) and the text" do
      announcement = described_class.new(subject: "News for {{first_name}}",
        body: "Hi {{ first_name }} {{last_name}},\n\n**Bold** at https://wisp.cals.wisc.edu\n\n- one\n\n{{name}} <{{email}}>")
      rendered = announcement.render_for(user)
      expect(rendered[:subject]).to eq("News for Ann")
      expect(rendered[:html]).to include("Hi Ann &lt;Lee&gt;,")
      expect(rendered[:html]).to include("<strong>Bold</strong>")
      expect(rendered[:html]).to include('<a href="https://wisp.cals.wisc.edu" style="color:#005b90;text-decoration:underline" ses:no-track>')
      expect(rendered[:html]).to include('<li style="margin:0 0 4px">one</li>')
      expect(rendered[:html]).to include("Ann &lt;Lee&gt;")
      expect(rendered[:text]).to start_with("Hi Ann <Lee>,\n\n**Bold**")

      nameless = build(:user, first_name: nil, email: "x@farm.test")
      expect(described_class.new(subject: "Hi {{first_name|there}}", body: "").render_for(nameless)[:subject]).to eq("Hi there")
    end

    it "leaves out raw HTML and unsafe links" do
      html = described_class.new(subject: "x", body: "<script>alert(1)</script> [x](javascript:alert(1))").render_for(user)[:html]
      expect(html).not_to include("<script")
      expect(html).not_to include("javascript:")
    end
  end

  it "rejects placeholders it doesn't know and needs a date for a dated audience" do
    announcement = described_class.new(subject: "{{firstname}}", body: "Hi", audience: "active_since")
    expect(announcement).not_to be_valid
    expect(announcement.errors[:body].sole).to include("{{firstname}}")
    expect(announcement.errors[:audience_date]).to be_present
  end

  describe "#send!" do
    let(:admin) { grower("staff@farm.test", admin: true) }
    let(:announcement) { described_class.create!(subject: "Hi", body: "News", audience: "all", created_by: admin) }

    it "freezes the recipients as deliveries and queues the job, once" do
      ann = grower("ann@farm.test")
      expect(announcement.send!(by: admin)).to be(true)
      expect(announcement).to have_attributes(status: "sending", sent_by: admin, recipients_count: 2)
      expect(announcement.deliveries.map(&:user)).to contain_exactly(admin, ann)
      expect(AnnouncementJob).to have_been_enqueued.with(announcement)

      grower("late@farm.test")
      expect(announcement.send!(by: admin)).to be(false)
      expect(announcement.deliveries.count).to eq(2)
    end

    it "stays a draft with no one to send to" do
      admin.update!(announcements: false)
      expect(announcement.send!(by: admin)).to be(false)
      expect(announcement.reload).to have_attributes(status: "draft", sent_at: nil)
    end
  end
end

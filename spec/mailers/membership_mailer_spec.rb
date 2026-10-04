require "rails_helper"

RSpec.describe MembershipMailer do
  it "tells someone who added them to which operation, and how to get there" do
    owner = create(:user, first_name: "Olive", last_name: "Owner", email: "olive@example.com")
    group = owner.groups.first
    group.update!(name: "Sands Farms")
    membership = create(:membership, group:, user: create(:user, email: "max@example.com"))

    mail = described_class.added(membership, owner)
    expect(mail.to).to eq(["max@example.com"])
    expect(mail.subject).to eq("You've been added to Sands Farms on WISP")
    expect(mail.text_part.body.decoded).to include("Olive Owner (olive@example.com) added you to Sands Farms on WISP as a member")
    expect(mail.html_part.body.decoded).to include("ses:no-track")
  end
end

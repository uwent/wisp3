require "rails_helper"

RSpec.describe UnconfirmedAccountPurgeJob do
  it "deletes accounts still unconfirmed a month after signing up, with their empty groups" do
    old = create(:user, :unconfirmed, created_at: 31.days.ago)
    group = old.groups.first
    recent = create(:user, :unconfirmed, created_at: 29.days.ago)
    confirmed = create(:user, created_at: 1.year.ago)
    admin = create(:user, :unconfirmed, admin: true, created_at: 1.year.ago)

    described_class.perform_now

    expect(User.exists?(old.id)).to be(false)
    expect(Group.exists?(group.id)).to be(false)
    expect(User.where(id: [recent, confirmed, admin].map(&:id)).count).to eq(3)
  end

  it "keeps an unconfirmed account in an operation with farms" do
    user = create(:user, :unconfirmed, created_at: 1.year.ago)
    create(:farm, group: user.groups.first)
    described_class.perform_now
    expect(User.exists?(user.id)).to be(true)
  end
end

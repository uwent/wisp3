require "rails_helper"

RSpec.describe User do
  describe "on create" do
    it "gets a personal group it administers" do
      user = create(:user, first_name: "Pat", last_name: "Grower")
      expect(user.groups.map(&:name)).to eq(["Pat Grower's farms"])
      expect(user.memberships.first).to be_admin
    end

    it "names the group after the email when there is no name" do
      user = create(:user, first_name: nil, last_name: nil, email: "pat@example.com")
      expect(user.groups.first.name).to eq("pat@example.com's farms")
    end
  end

  describe "validations" do
    it "rejects .ru addresses" do
      user = build(:user, email: "someone@mail.ru")
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("can't be from a .ru domain")
    end

    it "only allows known unit systems" do
      expect(build(:user, unit_system: "metric")).to be_valid
      expect(build(:user, unit_system: "furlongs")).not_to be_valid
    end
  end

  describe "#confirm_by_magic_link!" do
    it "confirms a never-confirmed account" do
      user = create(:user, :unconfirmed)
      user.confirm_by_magic_link!
      expect(user.reload).to be_confirmed
    end

    it "does not confirm a pending email change" do
      user = create(:user)
      user.update!(email: "new@example.com")
      expect(user.reload.unconfirmed_email).to eq("new@example.com")

      user.confirm_by_magic_link!
      expect(user.reload.email).not_to eq("new@example.com")
      expect(user.unconfirmed_email).to eq("new@example.com")
    end
  end

  describe "destroy" do
    it "deletes groups nobody else belongs to and keeps shared ones" do
      user = create(:user)
      personal = user.groups.first
      shared = create(:group)
      create(:membership, user:, group: shared)
      create(:membership, group: shared)

      user.destroy!

      expect(Group.exists?(personal.id)).to be(false)
      expect(Group.exists?(shared.id)).to be(true)
    end
  end
end

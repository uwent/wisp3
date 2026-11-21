require "rails_helper"

RSpec.describe Membership do
  let(:group) { create(:user).groups.first }
  let!(:first) { group.memberships.sole }
  let!(:second) { create(:membership, group:, owner: true) }

  def queries
    log = []
    recorder = ->(*, payload) { log << payload[:sql] unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(recorder, "sql.active_record") { yield }
    log
  end

  # Two owners demoting each other at once: each request checks for another owner, so the check
  # and the write happen under the group's row lock
  it "locks the group before checking for another owner, then demotes" do
    log = queries { expect(second.change_role(false)).to be_nil }
    lock = log.index { |sql| sql.match?(/FROM "groups".*FOR UPDATE/) }
    check = log.index { |sql| sql.match?(/FROM "memberships".*"memberships"."owner"/) }
    expect(lock).to be < check
    expect(second.reload).not_to be_owner
    expect(first.change_role(false)).to include("only owner")
    expect(first.reload).to be_owner
  end

  it "locks the group before checking it keeps an owner, then removes" do
    log = queries { expect(second.remove).to be_nil }
    lock = log.index { |sql| sql.match?(/FROM "groups".*FOR UPDATE/) }
    check = log.index { |sql| sql.match?(/FROM "memberships".*"memberships"."id" !=/) }
    expect(lock).to be < check
    expect(described_class.exists?(second.id)).to be(false)
    expect(first.remove).to include("only member")
  end
end

# Daily: deletes accounts that never confirmed their email within AFTER of signing up (nearly all
# spam sign-ups; their confirmation links expired after Devise's confirm_within). An account in an
# operation with farms is kept, which an unconfirmed one shouldn't be, but deleting farm data by
# mistake can't be undone.
class UnconfirmedAccountPurgeJob < ApplicationJob
  AFTER = 30.days

  def perform
    users = User.where(confirmed_at: nil, admin: false).where(created_at: ...AFTER.ago)
      .where.not(id: Membership.joins(group: :farms).select(:user_id))
    count = users.find_each.count(&:destroy!)
    Rails.logger.info("Deleted #{count} unconfirmed #{"account".pluralize(count)}") if count.positive?
  end
end

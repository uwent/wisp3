# Each morning after the 5 am weather refresh (config/recurring.yml): the daily digest to every user
# who has it on and a field in season (or a field needing water soon, for those who only want it
# then). users.digest_sent_on keeps a rerun from sending twice, and one user's failure doesn't stop
# the rest.
class DailyDigestJob < ApplicationJob
  def perform(today: Date.current)
    User.where.not(digest_frequency: "never").where.not(confirmed_at: nil)
      .where("digest_sent_on IS NULL OR digest_sent_on < ?", today).find_each do |user|
      digest = DailyDigest.new(user, today:)
      next unless digest.deliverable?

      DigestMailer.daily(digest).deliver_now
      user.update_column(:digest_sent_on, today)
    rescue => error
      Rails.error.report(error, context: {user_id: user.id})
    end
  end
end

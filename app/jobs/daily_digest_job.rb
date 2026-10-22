# Each morning after the 5 am weather refresh (config/recurring.yml): the daily digest to every user
# who has it on and a field in season (or a field needing water soon, for those who only want it
# then). users.digest_sent_on keeps a rerun from sending twice. One user's failure doesn't stop the
# rest, but the job fails at the end if any did, so it's listed as a failed job (HealthCheck) and
# retrying it sends only to those who missed out.
class DailyDigestJob < ApplicationJob
  class Incomplete < StandardError; end

  def perform(today: Date.current)
    sent = 0
    failures = {}
    User.where.not(digest_frequency: "never").where.not(confirmed_at: nil)
      .where("digest_sent_on IS NULL OR digest_sent_on < ?", today).find_each do |user|
      digest = DailyDigest.new(user, today:)
      next unless digest.deliverable?

      DigestMailer.daily(digest).deliver_now
      user.update_column(:digest_sent_on, today)
      sent += 1
    rescue => error
      Rails.error.report(error, context: {user_id: user.id})
      failures[user.id] = error
    end
    return if failures.empty?

    first = failures.values.first
    raise Incomplete, "#{failures.size} of #{sent + failures.size} daily emails failed " \
      "(users #{failures.keys.join(", ")}); first error: #{first.class}: #{first.message.lines.first&.strip}"
  end
end

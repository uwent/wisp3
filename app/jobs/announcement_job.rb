# Sends an announcement's pending deliveries (Announcement#send!, #resume!), one email at a time,
# THROTTLE apart to stay well under Amazon SES's sending rate (its lowest production quota is 14 a
# second). Each delivery is claimed before it's sent, so two runs never send the same one. Someone
# who unsubscribed or was unconfirmed since the send began is skipped. One failure doesn't stop the
# rest; the announcement ends sent, or incomplete when any failed (to be resumed from its page), and
# the job then fails so the morning health check lists it, as DailyDigestJob does.
class AnnouncementJob < ApplicationJob
  class Incomplete < StandardError; end

  # Runs for minutes on purpose; the bulk queue keeps it from holding up mail (config/queue.yml)
  queue_as :bulk

  THROTTLE = 0.2 # seconds: five emails a second

  def perform(announcement, throttle: THROTTLE)
    announcement.deliveries.where(status: "pending").includes(:user).find_each do |delivery|
      next unless delivery.claim!

      user = delivery.user
      if user.announcements? && user.confirmed?
        deliver(announcement, delivery, user)
        sleep throttle if throttle.positive?
      else
        delivery.update_columns(status: "skipped", updated_at: Time.current)
      end
      announcement.touch # shows the send is still moving (Announcement#stalled?)
    end

    progress = announcement.progress
    return if progress[:pending].positive? # another run still has some

    announcement.update!(status: progress[:failed].positive? ? "incomplete" : "sent")
    return if progress[:failed].zero?

    first = announcement.deliveries.where(status: "failed").first
    raise Incomplete, "#{progress[:failed]} of #{announcement.recipients_count} emails of announcement " \
      "#{announcement.id} failed; first error: #{first&.error}"
  end

  private

  def deliver(announcement, delivery, user)
    AnnouncementMailer.announcement(announcement, user).deliver_now
    delivery.update_columns(status: "sent", sent_at: Time.current, updated_at: Time.current)
  rescue => error
    Rails.error.report(error, context: {announcement_id: announcement.id, user_id: user.id})
    delivery.update_columns(status: "failed", error: "#{error.class}: #{error.message.lines.first&.strip}".truncate(250),
      updated_at: Time.current)
  end
end

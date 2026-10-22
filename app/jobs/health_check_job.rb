# Each morning after the daily digest (config/recurring.yml): runs HealthCheck, stores the result for
# the admin weather page and /up, and emails every confirmed admin when it finds problems. The admin
# page's "Re-run" runs it without the email.
class HealthCheckJob < ApplicationJob
  def perform(now: Time.current, notify: true)
    result = HealthCheck.run(now:)
    return if !notify || result.problems.empty?

    admins = User.where(admin: true).where.not(confirmed_at: nil).order(:email).pluck(:email)
    AdminMailer.health(result.problems, to: admins, now:).deliver_now if admins.any?
  end
end

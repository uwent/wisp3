# Each morning after the daily digest (config/recurring.yml): emails every confirmed admin what
# HealthCheck finds, or nothing when all is well
class HealthCheckJob < ApplicationJob
  def perform(now: Time.current)
    problems = HealthCheck.new(now:).problems
    return if problems.empty?

    admins = User.where(admin: true).where.not(confirmed_at: nil).order(:email).pluck(:email)
    AdminMailer.health(problems, to: admins, now:).deliver_now if admins.any?
  end
end

# Emails to WISP's admins: the morning health check (HealthCheckJob)
class AdminMailer < ApplicationMailer
  # problems: HealthCheck::Problems, one email to every admin
  def health(problems, to:, now: Time.current)
    @problems = problems
    @now = now
    @weather_url = admin_weather_url
    mail to:, subject: "WISP health check: #{problems.size} #{"problem".pluralize(problems.size)} " \
      "(#{now.strftime("%a, %b %-d")})"
  end
end

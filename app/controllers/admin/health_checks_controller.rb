module Admin
  # Re-running the health check from the weather page (PLAN.md Phase 8 B): stores the new result
  # without emailing the admins, as the morning run does
  class HealthChecksController < BaseController
    def create
      HealthCheckJob.perform_now(notify: false)
      redirect_to admin_weather_path, notice: "Health check re-run", status: :see_other
    end
  end
end

# /up: whether WISP is up, for uptime monitors and deploys (PLAN.md Phase 8 B). Public, so it gives
# only states and counts: no cells, errors or users. 200 while the app and its database answer (the
# body's status is "degraded" when the last health check found problems or the morning run was
# missed), 503 when the database doesn't.
class HealthController < ActionController::Base
  def show
    database = begin
      ActiveRecord::Base.connection.select_value("SELECT 1") && "ok"
    rescue => error
      Rails.error.report(error, handled: true)
      "error"
    end
    check = (database == "ok") ? last_check : nil
    status = if database != "ok" then "down"
    elsif check && (check[:overdue] || check[:problems].any?) then "degraded"
    else
      "ok"
    end

    response.headers["Cache-Control"] = "no-store"
    render status: (status == "down") ? :service_unavailable : :ok, json: {
      status:, time: Time.current.iso8601, version: self.class.version, database:, health_check: check
    }
  end

  # The deployed commit (Capistrano writes REVISION into each release), or nil
  def self.version
    return @version if defined?(@version)

    revision = Rails.root.join("REVISION")
    @version = revision.exist? ? revision.read.strip.first(7) : nil
  end

  private

  def last_check
    last = HealthCheck.last
    {checked_at: last&.checked_at&.iso8601, overdue: HealthCheck.overdue?,
     problems: last&.problems.to_a.to_h { |problem| [problem.kind, problem.details.size] }}
  end
end

# What needs an admin's attention (PLAN.md Phase 8 B): failed background jobs, stale or failing
# weather, and daily digests that were due this morning but not sent. Read from what's already
# stored; HealthCheckJob emails the problems to the admins each morning, and the admin weather page
# shows the same list.
class HealthCheck
  # details: Detail rows, with the user's id for a row about one user (linked to their admin page)
  Problem = Data.define(:kind, :summary, :details)
  Detail = Data.define(:text, :user_id) do
    def initialize(text:, user_id: nil) = super
  end

  # DailyDigestJob runs at 6 am Central (config/recurring.yml); by this time it has finished
  DIGEST_CHECKED_FROM = {hour: 6, min: 30}.freeze
  # Users listed by email when digests weren't sent
  DIGEST_USERS_LISTED = 5
  RECENT = 24.hours

  attr_reader :now

  def initialize(now: Time.current)
    @now = now
  end

  def problems = [failed_jobs, stale_weather, digest_not_sent].compact

  # [[job class, error class, error message, failed at]], or none where Solid Queue isn't the queue
  # adapter (development and test; its tables are in the queue database on the servers)
  def failed_executions
    return [] unless ActiveJob::Base.queue_adapter_name == "solid_queue"

    SolidQueue::FailedExecution.includes(:job).order(:created_at).map do |failed|
      [failed.job.class_name, failed.exception_class, failed.message, failed.created_at]
    end
  end

  private

  def failed_jobs
    failed = failed_executions
    return if failed.empty?

    recent = failed.count { |*, at| at > now - RECENT }
    details = failed.group_by(&:first).map do |job_class, rows|
      _, error_class, message, at = rows.max_by(&:last)
      count = rows.size
      fresh = rows.count { |*, failed_at| failed_at > now - RECENT }
      Detail.new(text: "#{job_class}: #{count} failed (#{fresh} in the last 24 h), latest #{ago(at)}: " \
        "#{[error_class, message.to_s.lines.first&.strip].compact_blank.join(": ")}")
    end
    Problem.new(kind: :failed_jobs, summary: "#{count(failed.size, "failed job")}, #{recent} new in the last 24 h",
      details:)
  end

  # Active cells missing yesterday's weather, not fetched or without a forecast for a day, and any
  # cell whose fetch failed in the last day
  def stale_weather
    active = WeatherCell.active(now.to_date).pluck(:id)
    cells = WeatherCell.where(id: active).or(WeatherCell.where(last_error_at: (now - RECENT)..)).order(:id).to_a
    latest_day = WeatherDay.where(weather_cell_id: active).group(:weather_cell_id).maximum(:date)
    latest_forecast = WeatherForecast.deterministic.where(weather_cell_id: active).group(:weather_cell_id)
      .maximum(:issued_at)

    details = cells.filter_map do |cell|
      failures = []
      if active.include?(cell.id)
        yesterday = now.in_time_zone(cell.time_zone).to_date - 1
        day = latest_day[cell.id]
        failures << (day ? "weather stored only through #{day}" : "no weather stored") if day.nil? || day < yesterday
        if cell.last_fetched_at.nil? || cell.last_fetched_at < now - RECENT
          failures << (cell.last_fetched_at ? "last fetched #{ago(cell.last_fetched_at)}" : "never fetched")
        end
        forecast = latest_forecast[cell.id]
        if forecast.nil? || forecast < now - RECENT
          failures << (forecast ? "forecast issued #{ago(forecast)}" : "no forecast")
        end
      end
      if cell.last_error_at && cell.last_error_at > now - RECENT
        failures << "fetch failed #{ago(cell.last_error_at)}: #{cell.last_error}"
      end
      next if failures.empty?

      Detail.new(text: "Cell #{cell.id} (#{format("%.4f, %.4f", cell.latitude, cell.longitude)}): " \
        "#{failures.join("; ")}")
    end
    return if details.empty?

    Problem.new(kind: :stale_weather, summary: "#{count(details.size, "weather cell")} stale or failing", details:)
  end

  # The users DailyDigestJob would have sent today's digest to but didn't, once it has run
  def digest_not_sent
    central = now.in_time_zone("America/Chicago")
    return if central < central.change(**DIGEST_CHECKED_FROM)

    today = central.to_date
    users = User.where.not(digest_frequency: "never").where.not(confirmed_at: nil)
      .where("digest_sent_on IS NULL OR digest_sent_on < ?", today).order(:email)
      .select { |user| DailyDigest.new(user, today:).deliverable? }
    return if users.empty?

    details = users.first(DIGEST_USERS_LISTED).map { |user| Detail.new(text: user.email, user_id: user.id) }
    details << Detail.new(text: "and #{users.size - DIGEST_USERS_LISTED} more") if users.size > DIGEST_USERS_LISTED
    Problem.new(kind: :digest_not_sent, summary: "#{count(users.size, "user")} didn't get today's daily email",
      details:)
  end

  def count(n, noun) = "#{n} #{noun.pluralize(n)}"

  def ago(time)
    hours = ((now - time) / 1.hour).floor
    (hours < 1) ? "under an hour ago" : "#{hours} h ago"
  end
end

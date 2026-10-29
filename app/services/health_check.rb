# What needs an admin's attention (PLAN.md Phase 8 B): background jobs that failed since the last
# check, and weather that's missing for the cells in use. It reports the state of the data, which
# clears itself once the data arrives, rather than every failure along the way. HealthCheckJob runs
# it each morning and stores the result, which the admin weather page and /up show.
class HealthCheck
  Problem = Data.define(:kind, :summary, :details)
  # A run, as stored
  Result = Data.define(:checked_at, :problems)

  CACHE_KEY = "health_check/last"
  RECENT = 24.hours
  # Weather is checked over the days before today
  WEATHER_DAYS = 7
  # The morning run (7 am) counts as missed once the last result is this old
  OVERDUE = 26.hours

  # Checks now and stores the result. Failed jobs are counted since the previous run.
  def self.run(now: Time.current)
    problems = new(now:, since: last&.checked_at).problems
    Rails.cache.write(CACHE_KEY, {checked_at: now, problems: problems.map(&:to_h)})
    Result.new(checked_at: now, problems:)
  end

  # The last stored run, or nil
  def self.last
    stored = Rails.cache.read(CACHE_KEY) or return
    Result.new(checked_at: stored[:checked_at], problems: stored[:problems].map { |problem| Problem.new(**problem) })
  end

  # Whether the morning run has been missed, where jobs run (Solid Queue, on the servers)
  def self.overdue?(now: Time.current)
    solid_queue? && (last.nil? || last.checked_at < now - OVERDUE)
  end

  def self.solid_queue? = ActiveJob::Base.queue_adapter_name == "solid_queue"

  attr_reader :now, :since

  def initialize(now: Time.current, since: nil)
    @now = now
    @since = since || now - RECENT
  end

  def problems = [failed_jobs, missing_weather].compact

  # [[job class, error class, error message, failed at]] since the last check, or none where Solid
  # Queue isn't the queue adapter (development and test; its tables are in the queue database on the
  # servers). Failed executions older than a week are discarded (config/recurring.yml).
  def failed_executions
    return [] unless self.class.solid_queue?

    SolidQueue::FailedExecution.includes(:job).where(created_at: since..).order(:created_at).map do |failed|
      error = failed.error || {}
      [failed.job.class_name, error["exception_class"], error["message"], failed.created_at]
    end
  end

  private

  def failed_jobs
    failed = failed_executions
    return if failed.empty?

    details = failed.group_by(&:first).map do |job_class, rows|
      _, error_class, message, at = rows.max_by(&:last)
      error = [error_class, message.to_s.lines.first&.strip].compact_blank.join(": ")
      ["#{job_class}: #{rows.size} failed, latest #{ago(at)}", error.presence].compact.join(": ")
    end
    Problem.new(kind: :failed_jobs, summary: "#{count(failed.size, "job")} failed since the last check", details:)
  end

  # Cells in use with days missing or without ET or precipitation in the last week, or without a
  # forecast for a day; and any cell whose fetch failed in the last day
  def missing_weather
    today = now.to_date
    window = (today - WEATHER_DAYS)..(today - 1)
    active = WeatherCell.active(today).order(:id).to_a
    failing = WeatherCell.where(last_error_at: (now - RECENT)..).where.not(id: active.map(&:id)).order(:id).to_a
    days = WeatherDay.where(weather_cell_id: active.map(&:id), date: window).group(:weather_cell_id)
      .pluck(:weather_cell_id, Arel.sql("count(*)"),
        Arel.sql("count(*) FILTER (WHERE et0_in IS NULL OR precip_in IS NULL)"))
      .to_h { |id, *counts| [id, counts] }
    forecasts = WeatherForecast.deterministic.where(weather_cell_id: active.map(&:id)).group(:weather_cell_id)
      .maximum(:issued_at)

    details = (active + failing).filter_map do |cell|
      failures = []
      if active.include?(cell)
        stored, empty = days.fetch(cell.id, [0, 0])
        missing = window.count - stored
        failures << "#{count(missing, "day")} missing in the last #{WEATHER_DAYS}" if missing.positive?
        failures << "#{count(empty, "day")} without ET or precipitation" if empty.positive?
        forecast = forecasts[cell.id]
        failures << (forecast ? "forecast issued #{ago(forecast)}" : "no forecast") if !forecast || forecast < now - RECENT
      end
      failures << "fetch failed #{ago(cell.last_error_at)}: #{cell.last_error}" if cell.last_error_at&.after?(now - RECENT)
      next if failures.empty?

      "Cell #{cell.id} (#{format("%.4f, %.4f", cell.latitude, cell.longitude)}): #{failures.join("; ")}"
    end
    return if details.empty?

    Problem.new(kind: :missing_weather, summary: "#{count(details.size, "weather cell")} missing weather", details:)
  end

  def count(n, noun) = "#{n} #{noun.pluralize(n)}"

  def ago(time)
    hours = ((now - time) / 1.hour).floor
    (hours < 1) ? "under an hour ago" : "#{hours} h ago"
  end
end

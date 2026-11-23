module Admin
  # Weather status: API mode and usage, and each cell's coverage, forecast and errors,
  # below the last health check's result (HealthCheck)
  class WeatherController < BaseController
    def show
      client = Weather::OpenMeteo.new
      limiter = Weather::RateLimiter.new
      render inertia: "Admin/Weather", props: {
        health_check:,
        api: {
          mode: client.mode.to_s,
          model: Weather::OpenMeteo.primary_models.join(", "),
          soil_model: Weather::OpenMeteo::SOIL_MODEL,
          usage: %i[minute hour day].to_h { |period| [period, limiter.used(period).round(1)] },
          limits: (client.mode == :free) ? Weather::RateLimiter::FREE_LIMITS : nil
        },
        cells: WeatherCellStatusSerializer.new(WeatherCellStatus.all).serializable_hash,
        pending_jobs: WeatherJob.pending,
        weather_corrections: Weather::Corrections.summaries
      }
    end

    def refresh
      WeatherRefreshJob.perform_later(all: true)
      redirect_to admin_weather_path, notice: "Weather refresh queued for every cell with a system", status: :see_other
    end

    private

    # The last health check's result as stored by HealthCheckJob (not run on each visit)
    def health_check
      last = HealthCheck.last
      {checked_at: last&.checked_at&.iso8601, overdue: HealthCheck.overdue?, problems: last&.problems&.map(&:to_h) || []}
    end
  end
end

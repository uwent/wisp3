module Admin
  # Weather status (PLAN.md §12): API mode and usage, and each cell's coverage, forecast and errors,
  # below the morning health check's problems (HealthCheck, PLAN.md Phase 8 B)
  class WeatherController < BaseController
    def show
      client = Weather::OpenMeteo.new
      limiter = Weather::RateLimiter.new
      render inertia: "Admin/Weather", props: {
        problems: HealthCheck.new.problems.map do |problem|
          {kind: problem.kind, summary: problem.summary, details: problem.details.map(&:to_h)}
        end,
        api: {
          mode: client.mode.to_s,
          model: Weather::OpenMeteo.primary_models.join(", "),
          soil_model: Weather::OpenMeteo::SOIL_MODEL,
          usage: %i[minute hour day].to_h { |period| [period, limiter.used(period).round(1)] },
          limits: (client.mode == :free) ? Weather::RateLimiter::FREE_LIMITS : nil
        },
        cells: WeatherCellStatusSerializer.new(WeatherCellStatus.all).serializable_hash,
        pending_jobs: WeatherJob.pending
      }
    end

    def refresh
      WeatherRefreshJob.perform_later(all: true)
      redirect_to admin_weather_path, notice: "Weather refresh queued for every cell with a pivot", status: :see_other
    end
  end
end

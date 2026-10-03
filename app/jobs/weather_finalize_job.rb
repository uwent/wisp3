# Daily: days more than a week old are final, and refreshes no longer overwrite them
class WeatherFinalizeJob < WeatherJob
  def perform
    WeatherDay.where(final: false).where(date: ...(Date.current - Weather::Fetcher::PAST_DAYS)).update_all(final: true)
  end
end

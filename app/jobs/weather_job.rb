# Base for weather jobs: retries Open-Meteo outages and rate limits, gives up on bad requests
class WeatherJob < ApplicationJob
  queue_as :weather

  retry_on Weather::RateLimited, attempts: 10, wait: ->(executions) { 5.minutes * executions }
  retry_on Weather::TransientError, attempts: 5, wait: :polynomially_longer
end

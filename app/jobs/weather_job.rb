# Base for weather jobs: retries Open-Meteo outages and rate limits, gives up on bad requests.
# Keeps a count of weather jobs queued or running (retries waiting included) in Rails.cache, so the
# admin page knows to keep reloading while there are some.
class WeatherJob < ApplicationJob
  PENDING_KEY = "weather-jobs:pending"

  queue_as :weather

  retry_on Weather::RateLimited, attempts: 10, wait: ->(executions) { 5.minutes * executions }
  retry_on Weather::TransientError, attempts: 5, wait: :polynomially_longer

  # A retry is enqueued after the failed run's ensure, so the count goes down then back up. Jobs
  # run with perform_now were never counted. The key expires an hour after the last enqueue, in
  # case a process dies mid-job.
  after_enqueue { Rails.cache.increment(PENDING_KEY, 1, expires_in: 1.hour) }
  around_perform do |job, block|
    block.call
  ensure
    Rails.cache.decrement(PENDING_KEY, 1) if job.enqueued_at
  end

  def self.pending = [Rails.cache.read(PENDING_KEY, raw: true).to_i, 0].max
end

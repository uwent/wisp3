module Weather
  # Keeps Open-Meteo usage under its limits, counted the way Open-Meteo counts: per location, a
  # request with more than 10 variables or more than 2 weeks of data counts as several calls
  # (variables / 10 × days / 14). Counters live in Rails.cache, so they're shared across processes.
  # Over the per-minute limit, it waits for the next minute; over the hourly or daily limit, it
  # raises RateLimited and the job retries later.
  class RateLimiter
    # The free API's published limits, with some headroom
    FREE_LIMITS = {minute: 500, hour: 4_500, day: 9_000}.freeze

    def initialize(limits: FREE_LIMITS, sleeper: ->(seconds) { sleep(seconds) })
      @limits, @sleeper = limits, sleeper
    end

    def self.weight(locations:, variables:, days:)
      locations * [1.0, (variables / 10.0) * (days / 14.0)].max
    end

    def acquire!(weight)
      return if @limits.blank?
      @limits.each do |period, limit|
        next if used(period) + weight <= limit
        raise RateLimited.new("Open-Meteo #{period} limit reached", retry_in: seconds_left(period)) unless period == :minute
        @sleeper.call(seconds_left(:minute))
      end
      @limits.each_key { |period| Rails.cache.increment(key(period), (weight * 100).ceil, expires_in: length(period)) }
    end

    def used(period) = Rails.cache.read(key(period), raw: true).to_i / 100.0

    private

    def length(period) = {minute: 1.minute, hour: 1.hour, day: 1.day}.fetch(period)
    def key(period) = "open-meteo-usage:#{period}:#{Time.current.to_i / length(period).to_i}"
    def seconds_left(period) = length(period).to_i - Time.current.to_i % length(period).to_i
  end
end

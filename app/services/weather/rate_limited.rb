module Weather
  # Over Open-Meteo's hourly or daily limit (Weather::RateLimiter)
  class RateLimited < TransientError
    attr_reader :retry_in

    def initialize(message = "Open-Meteo rate limit reached", retry_in: 60)
      super(message)
      @retry_in = retry_in
    end
  end
end

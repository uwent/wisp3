module Weather
  # A request that won't succeed if retried (bad parameters, an unknown model)
  class Error < StandardError; end
end

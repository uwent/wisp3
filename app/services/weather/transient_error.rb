module Weather
  # Network failures, 429s and 5xx responses: worth retrying later
  class TransientError < Error; end
end

# Counts events per key in fixed time windows (Rails.cache), so unlike Rails' rate_limit it can
# say when the limit lifts and can be reset, e.g. when the user signs in.
class WindowLimit
  def initialize(key, limit:, window:)
    @key, @limit, @window = key, limit, window
  end

  # Counts one event; false (and not counted) if the limit is already reached this window
  def allow!
    return false if exceeded?
    Rails.cache.increment(cache_key, 1, expires_in: @window)
    true
  end

  def exceeded?
    Rails.cache.read(cache_key, raw: true).to_i >= @limit
  end

  def reset!
    Rails.cache.delete(cache_key)
  end

  # Seconds until the current window ends
  def retry_in
    (@window.to_i - Time.current.to_i % @window.to_i)
  end

  # "Please try again in 12 minutes."
  def retry_message
    minutes = (retry_in / 60.0).ceil
    "Please try again in #{minutes} #{"minute".pluralize(minutes)}."
  end

  private

  def cache_key
    "window-limit:#{@key}:#{Time.current.to_i / @window.to_i}"
  end
end

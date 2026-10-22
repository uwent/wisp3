# Request throttling and blocking, carried over from the legacy app with paths updated.
# Per-address limits on sign-in emails live in MagicLinksController (WindowLimit).
class Rack::Attack
  Rack::Attack.cache.store = Rails.cache

  AUTH_POSTS = %r{\A/account(/sign_in|/sign_in_link|/sign_in_code|/password|/confirmation)?\z}

  safelist("allow from localhost") do |req|
    ["127.0.0.1", "::1"].include?(req.ip)
  end

  throttle("req/ip", limit: 25, period: 1.second) do |req|
    req.ip
  end

  throttle("writes/ip", limit: 5, period: 1.second) do |req|
    req.ip if %w[POST PUT PATCH DELETE].include?(req.request_method)
  end

  # Sign-in, sign-up (POST /account), sign-in links and codes, password resets, confirmation resends
  throttle("auth/ip", limit: 5, period: 20.seconds) do |req|
    req.ip if req.post? && req.path.match?(AUTH_POSTS)
  end

  throttle("registration/ip", limit: 5, period: 1.hour) do |req|
    req.ip if req.post? && req.path == "/account"
  end

  throttle("password_reset/ip", limit: 3, period: 1.hour) do |req|
    req.ip if req.post? && req.path == "/account/password"
  end

  # Password guesses at one account from many addresses, which the per-IP limits don't catch. A
  # limit rather than a lockout, so nobody can lock a grower out by failing on purpose; sign-in
  # links and codes still work meanwhile.
  throttle("sign_in/email", limit: 10, period: 15.minutes) do |req|
    sign_in_email(req) if req.post? && req.path == "/account/sign_in"
  end

  # The email in a sign-in POST, normalized. Inertia sends forms as JSON, which Rack doesn't parse.
  def self.sign_in_email(req)
    params = if req.media_type == "application/json"
      body = req.body.read
      req.body.rewind
      JSON.parse(body)
    else
      req.POST
    end
    params.is_a?(Hash) && params.dig("user", "email").to_s.strip.downcase.presence
  rescue JSON::ParserError
    nil
  end

  blocklist("login scrapers") do |req|
    Allow2Ban.filter(req.ip, maxretry: 20, findtime: 1.minute, bantime: 1.hour) do
      req.post? && req.path == "/account/sign_in"
    end
  end

  blocklist("pentesters") do |req|
    Fail2Ban.filter("pentesters-#{req.ip}", maxretry: 3, findtime: 10.minutes, bantime: 5.minutes) do
      path = req.path
      CGI.unescape(req.query_string).include?("/etc/passwd") ||
        path.include?("/etc/passwd") || path.match?(%r{/\.git/}) ||
        %w[wp-admin wp-login wp-config.php phpMyAdmin .env config.php].any? { |s| path.include?(s) }
    end
  end

  blocklist("bad user agents") do |req|
    ua = req.user_agent.to_s.downcase
    ua.empty? || ua == "-" || %w[sqlmap nmap nikto masscan zap].any? { |s| ua.include?(s) }
  end

  blocklist("sensitive files") do |req|
    req.path.match?(/\.(log|sql|backup|bak|old|tmp)\z/) ||
      %w[database.yml secrets.yml .env].any? { |s| req.path.include?(s) }
  end

  self.throttled_responder = lambda do |req|
    message = if req.env["rack.attack.matched"] == "sign_in/email"
      "Too many sign-in attempts for this account. Wait 15 minutes, or sign in with an emailed link instead.\n"
    else
      "Too many requests. Please wait a moment and try again.\n"
    end
    [429, {"content-type" => "text/plain"}, [message]]
  end
  self.blocklisted_responder = ->(_req) { [403, {"content-type" => "text/plain"}, ["Forbidden\n"]] }
end

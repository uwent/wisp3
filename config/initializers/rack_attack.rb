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

  self.throttled_responder = ->(_req) { [429, {"content-type" => "text/plain"}, ["Too many requests. Please wait a moment and try again.\n"]] }
  self.blocklisted_responder = ->(_req) { [403, {"content-type" => "text/plain"}, ["Forbidden\n"]] }
end

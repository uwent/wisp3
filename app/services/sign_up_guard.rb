# Tells scripted sign-ups from people without a CAPTCHA. The sign-up page carries a signed token of
# when it was shown and a hidden field people never see (a honeypot). A submission that fills in the
# hidden field, or comes back sooner than a person could type, is a bot; one without a valid token
# (posted without loading the page, or from a page left open for over a day) has to try again.
class SignUpGuard
  MIN_SECONDS = 3
  TOKEN_TTL = 1.day
  # The honeypot's name, a field bots tend to fill
  HONEYPOT = :website

  # The page's token: the one this browser was given before while it's still good (so coming back
  # to the form after a validation error doesn't restart the clock), or a new one
  def self.token(existing = nil, now: Time.current)
    shown_at(existing) ? existing : verifier.generate(now.to_f, expires_in: TOKEN_TTL)
  end

  # :ok, :bot or :stale
  def self.check(token:, honeypot:, now: Time.current)
    return :bot if honeypot.present?
    shown_at = shown_at(token)
    return :stale unless shown_at
    (now.to_f - shown_at < MIN_SECONDS) ? :bot : :ok
  end

  def self.shown_at(token)
    value = verifier.verified(token.to_s)
    value if value.is_a?(Numeric)
  end

  def self.verifier = Rails.application.message_verifier(:sign_up_form)
end

# Limits the emails a form sends to one address (confirmation resends, password resets), so nobody
# can flood someone's inbox from many IP addresses, which Rack::Attack's per-IP limits don't catch.
# Counted whether or not an account uses the address, so the limit doesn't reveal which do.
module LimitsEmailsPerAddress
  extend ActiveSupport::Concern

  EMAILS_PER_ADDRESS = 3
  WINDOW = 1.hour

  included do
    before_action :limit_emails_per_address, only: :create
  end

  private

  def limit_emails_per_address
    email = params.dig(:user, :email).to_s.strip.downcase
    return if email.blank?

    limit = WindowLimit.new("#{controller_name}-emails:#{email}", limit: EMAILS_PER_ADDRESS, window: WINDOW)
    return if limit.allow!

    redirect_to form_path_for_errors, status: :see_other,
      alert: "We've sent several emails to that address already. #{limit.retry_message}"
  end
end

# Turning the daily digest off from the email's link, without signing in. Mail providers POST
# one-click unsubscribes (RFC 8058) without a CSRF token; the token in the URL identifies the user.
class DigestUnsubscribesController < InertiaController
  skip_forgery_protection only: :create

  def show
    user = User.find_by_token_for(:digest_unsubscribe, params[:token])
    render inertia: "Auth/Unsubscribe", props: {token: params[:token], valid: user.present?, done: user && !user.digest?}
  end

  def create
    user = User.find_by_token_for(:digest_unsubscribe, params[:token])
    user&.update!(digest_frequency: "never")
    render inertia: "Auth/Unsubscribe", props: {token: params[:token], valid: user.present?, done: user.present?}
  end
end

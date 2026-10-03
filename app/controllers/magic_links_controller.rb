# Passwordless sign-in. Each request emails a one-time link and a six-digit code (for typing in
# on the device that asked, when the email is read elsewhere). Link tokens are stateless
# (User.generates_token_for :magic_login); codes are stored as an HMAC (User#generate_sign_in_code!).
# Both expire after 15 minutes and stop working once the user signs in.
class MagicLinksController < InertiaController
  before_action :redirect_signed_in_user

  TOO_MANY = "Too many sign-in emails requested. Please wait a while and try again."

  # 5 requests per address and 20 per IP each hour, so the form can't be used to flood an inbox
  rate_limit to: 5, within: 1.hour, only: :create, name: "per-email",
    by: -> { params[:email].to_s.strip.downcase },
    with: -> { redirect_to new_user_session_path, alert: TOO_MANY }
  rate_limit to: 20, within: 1.hour, only: :create, name: "per-ip",
    with: -> { redirect_to new_user_session_path, alert: TOO_MANY }
  # Guessing codes is also capped per code (User::SIGN_IN_CODE_ATTEMPTS)
  rate_limit to: 20, within: 15.minutes, only: :verify, name: "verify-per-ip",
    with: -> { redirect_to sign_in_code_path, alert: "Too many attempts. Please wait a while and try again." }

  def create
    email = params[:email].to_s.strip.downcase
    if email.blank?
      return redirect_to new_user_session_path, inertia: {errors: {email: ["Enter your email address"]}}
    end

    # Behaves the same whether or not the account exists. The resend cooldown is checked against
    # this browser's last request and the account's last code, so it holds across browsers too.
    resending = email == session[:sign_in_email]
    unless resending && resend_in.positive?
      user = User.find_by(email:)
      if user && !user.sign_in_code_recently_sent?
        MagicLinkMailer.sign_in_link(user, user.generate_token_for(:magic_login), user.generate_sign_in_code!).deliver_later
      end
      session[:sign_in_email] = email
      session[:sign_in_requested_at] = Time.current.to_i
      flash[:notice] = "We've sent a new code. Only the newest code works." if resending
    end

    redirect_to sign_in_code_path
  end

  # "Check your email": enter the code, or resend after the cooldown
  def code
    return redirect_to new_user_session_path unless session[:sign_in_email]

    render inertia: "Auth/SignInCode", props: {
      email: session[:sign_in_email],
      ttl_minutes: User::MAGIC_LINK_TTL.in_minutes.to_i,
      resend_in:
    }
  end

  def verify
    return redirect_to new_user_session_path unless session[:sign_in_email]

    user = User.find_by(email: session[:sign_in_email])
    unless user&.redeem_sign_in_code!(params[:code])
      return redirect_to sign_in_code_path, inertia: {errors: {code: [
        "That code is wrong or has expired. Codes expire after #{User::MAGIC_LINK_TTL.in_minutes.to_i} minutes " \
        "and stop working after #{User::SIGN_IN_CODE_ATTEMPTS} wrong tries; you can send a new one below."
      ]}}
    end

    sign_in_from_email(user)
  end

  # Landing page from the email. It only shows a button; using the link takes a POST, so email
  # security scanners that pre-fetch links can't spend the token.
  def show
    render inertia: "Auth/MagicLink", props: {
      token: params[:token],
      valid: User.find_by_token_for(:magic_login, params[:token]).present?,
      ttl_minutes: User::MAGIC_LINK_TTL.in_minutes.to_i
    }
  end

  def redeem
    user = User.find_by_token_for(:magic_login, params[:token])
    unless user
      return redirect_to new_user_session_path,
        alert: "That sign-in link has expired or was already used. Request a new one below."
    end

    sign_in_from_email(user)
  end

  private

  def redirect_signed_in_user
    redirect_to root_path if user_signed_in?
  end

  def sign_in_from_email(user)
    user.confirm_by_magic_link!
    session.delete(:sign_in_email)
    session.delete(:sign_in_requested_at)
    sign_in(:user, user) # updates current_sign_in_at, which invalidates the link and the code
    redirect_to after_sign_in_path_for(user), notice: "Signed in", status: :see_other
  end

  # Seconds until this browser may request another email
  def resend_in
    sent_at = session[:sign_in_requested_at].to_i
    [sent_at + User::SIGN_IN_CODE_RESEND_AFTER.to_i - Time.current.to_i, 0].max
  end
end

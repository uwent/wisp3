# One-time sign-in links ("email me a link"). Tokens are stateless (User.generates_token_for
# :magic_login): they expire after 15 minutes and stop working once the user signs in.
class MagicLinksController < InertiaController
  before_action :redirect_signed_in_user

  # 5 requests per address and 20 per IP each hour, so the form can't be used to flood an inbox
  rate_limit to: 5, within: 1.hour, only: :create, name: "per-email",
    by: -> { params[:email].to_s.strip.downcase },
    with: -> { redirect_to new_user_session_path, alert: "Too many sign-in links requested. Please wait a while and try again." }
  rate_limit to: 20, within: 1.hour, only: :create, name: "per-ip",
    with: -> { redirect_to new_user_session_path, alert: "Too many sign-in links requested. Please wait a while and try again." }

  def create
    email = params[:email].to_s.strip.downcase
    if email.blank?
      return redirect_to new_user_session_path, inertia: {errors: {email: ["Enter your email address"]}}
    end

    if (user = User.find_by(email:))
      MagicLinkMailer.sign_in_link(user, user.generate_token_for(:magic_login)).deliver_later
    end

    # Same response whether or not the account exists
    redirect_to new_user_session_path(email:),
      notice: "If there's an account for #{email}, we've emailed it a sign-in link. The link works once and expires in #{User::MAGIC_LINK_TTL.in_minutes.to_i} minutes."
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

    user.confirm_by_magic_link!
    sign_in(:user, user) # updates current_sign_in_at, which invalidates the link
    redirect_to after_sign_in_path_for(user), notice: "Signed in", status: :see_other
  end

  private

  def redirect_signed_in_user
    redirect_to root_path if user_signed_in?
  end
end

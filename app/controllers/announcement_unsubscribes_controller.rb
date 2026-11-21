# Turning announcements off from the email's link, without signing in, as the daily digest's
# (DigestUnsubscribesController). It leaves the digest's setting alone.
class AnnouncementUnsubscribesController < InertiaController
  skip_forgery_protection only: :create

  def show
    user = User.find_by_token_for(:announcement_unsubscribe, params[:token])
    render_page user, done: user && !user.announcements?
  end

  def create
    user = User.find_by_token_for(:announcement_unsubscribe, params[:token])
    user&.update!(announcements: false)
    render_page user, done: user.present?
  end

  private

  def render_page(user, done:)
    render inertia: "Auth/Unsubscribe", props: {kind: "announcements", token: params[:token], valid: user.present?, done:}
  end
end

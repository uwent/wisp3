class MagicLinkMailer < ApplicationMailer
  def sign_in_link(user, token)
    @user = user
    @url = magic_link_url(token:)
    @ttl_minutes = User::MAGIC_LINK_TTL.in_minutes.to_i
    mail to: user.email, subject: "Your WISP sign-in link"
  end
end

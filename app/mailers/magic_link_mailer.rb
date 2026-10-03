class MagicLinkMailer < ApplicationMailer
  def sign_in_link(user, token, code)
    @user = user
    @url = magic_link_url(token:)
    @code = code
    @ttl_minutes = User::MAGIC_LINK_TTL.in_minutes.to_i
    # The code goes in the subject so it shows in notification previews
    mail to: user.email, subject: "WISP sign-in code: #{code}"
  end
end

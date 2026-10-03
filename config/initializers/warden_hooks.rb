# A successful sign-in (password, link or code) shows the user has their account in hand, so
# lift the limit on sign-in emails to their address and the resend cooldown in this browser.
Warden::Manager.after_set_user except: :fetch do |user, auth, _opts|
  MagicLinksController.email_limit(user.email).reset! if user.is_a?(User)
  auth.raw_session.delete("sign_in_requested_at")
end

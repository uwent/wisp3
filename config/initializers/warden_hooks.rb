# A successful sign-in (password, link or code) shows the user has their account in hand, so
# lift the limits on sign-in emails to their address and on wrong codes for it, and the resend
# cooldown in this browser.
Warden::Manager.after_set_user except: :fetch do |user, auth, _opts|
  if user.is_a?(User)
    MagicLinksController.email_limit(user.email).reset!
    MagicLinksController.wrong_code_limit(user.email).reset!
  end
  auth.raw_session.delete("sign_in_requested_at")
end

# An admin's announcement (Announcement) to one account, in WISP's email layout, sent by
# AnnouncementJob, as a test to the admin, and rendered for the composer's preview. Replies go to
# WISP's own address, which reaches the team.
class AnnouncementMailer < ApplicationMailer
  # The email as it would go to the user: {subject:, html:}, for the composer's preview
  def self.preview(announcement, user)
    mail = announcement(announcement, user)
    {subject: mail.subject, html: mail.html_part.body.decoded}
  end

  def announcement(announcement, user, test: false)
    @content = announcement.render_for(user)
    @test = test
    @unsubscribe_url = announcement_unsubscribe_url(token: user.generate_token_for(:announcement_unsubscribe))
    @settings_url = settings_url
    # One-click unsubscribe (RFC 8058): mail providers POST to the link
    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    mail to: user.email, reply_to: Rails.configuration.x.mailer_from,
      subject: test ? "[Test] #{@content[:subject]}" : @content[:subject]
  end
end

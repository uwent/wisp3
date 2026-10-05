# The daily digest (PLAN.md Phase 6), sent by DailyDigestJob, and as a test from the Alerts page.
# Takes a DailyDigest, which the job and the previews build first to check there's something to send.
class DigestMailer < ApplicationMailer
  helper :digest
  helper_method :field_link, :pivot_link, :status_label, :status_style

  # The app's --color-status-* tokens in hex, with an icon so color isn't the only cue (StatusBadge)
  STATUSES = {
    irrigate: {label: "▲ Irrigate", color: "#cc2827", text: "#ffffff"},
    caution: {label: "! Caution", color: "#e49e22", text: "#141b24"},
    ok: {label: "✓ OK", color: "#0e9254", text: "#ffffff"},
    full: {label: "● Full", color: "#0077c2", text: "#ffffff"}
  }.freeze

  # What a user's digest would be today, for the previews on the Alerts page and admin user page:
  # the email whenever a field is in season, and why it wouldn't be sent, if it wouldn't
  def self.preview(digest)
    mail = daily(digest) if digest.entries.any?
    {skip_reason: digest.skip_reason, subject: mail&.subject, html: mail&.html_part&.body&.decoded}
  end

  # Today's digest, sent now from the Alerts page whatever the user's frequency
  def test_daily(user) = daily(DailyDigest.new(user), test: true)

  def daily(digest, test: false)
    @digest = digest
    @user = digest.user
    @test = test
    @unsubscribe_url = digest_unsubscribe_url(token: @user.generate_token_for(:digest_unsubscribe))
    @alerts_url = alerts_url
    # One-click unsubscribe (RFC 8058): mail providers POST to the link
    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    mail to: @user.email, subject: test ? "[Test] #{digest.subject}" : digest.subject,
      template_name: "daily"
  end

  private

  # A field's page, switching to its operation (the link may be read with another one current)
  def field_link(entry) = field_url(entry.field, operation: entry.group.id)

  def pivot_link(pivot) = pivot_url(pivot, operation: pivot.farm.group_id)

  def status_label(status) = STATUSES.dig(status, :label) || "No status"

  # Inline styles for a status badge (email clients ignore stylesheets)
  def status_style(status)
    style = STATUSES[status] || {color: "#e5e7eb", text: "#141b24"}
    "background:#{style[:color]};color:#{style[:text]};border-radius:999px;padding:2px 8px;font-size:12px;" \
      "font-weight:600;white-space:nowrap"
  end
end

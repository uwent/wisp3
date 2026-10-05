# The daily digest (PLAN.md Phase 6), sent by DailyDigestJob. Takes a DailyDigest, which the job
# and the admin preview build first to check there's something to send.
class DigestMailer < ApplicationMailer
  helper :digest
  helper_method :field_link, :status_label, :status_style

  # The app's --color-status-* tokens in hex, with an icon so color isn't the only cue (StatusBadge)
  STATUSES = {
    irrigate: {label: "▲ Irrigate", color: "#cc2827", text: "#ffffff"},
    caution: {label: "! Caution", color: "#e49e22", text: "#141b24"},
    ok: {label: "✓ OK", color: "#0e9254", text: "#ffffff"},
    full: {label: "● Full", color: "#0077c2", text: "#ffffff"}
  }.freeze

  def daily(digest)
    @digest = digest
    @user = digest.user
    @unsubscribe_url = digest_unsubscribe_url(token: @user.generate_token_for(:digest_unsubscribe))
    @settings_url = settings_url(anchor: "digest")
    # One-click unsubscribe (RFC 8058): mail providers POST to the link
    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    mail to: @user.email, subject: digest.subject
  end

  private

  # A field's page, switching to its operation (the link may be read with another one current)
  def field_link(entry) = field_url(entry.field, operation: entry.group.id)

  def status_label(status) = STATUSES.dig(status, :label) || "No status"

  # Inline styles for a status badge (email clients ignore stylesheets)
  def status_style(status)
    style = STATUSES[status] || {color: "#e5e7eb", text: "#141b24"}
    "background:#{style[:color]};color:#{style[:text]};border-radius:999px;padding:2px 8px;font-size:12px;" \
      "font-weight:600;white-space:nowrap"
  end
end

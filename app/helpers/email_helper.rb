module EmailHelper
  # The app's color tokens (application.css) in hex, since mail clients can't read CSS variables or
  # oklch(); change both together. Text colors pass WCAG AA on white and on uw_gray_lightest.
  COLORS = {
    white: "#ffffff",
    ink: "#141b24",
    muted: "#555f69",
    line: "#d9dfe5",
    brand: "#0071aa",
    brand_dark: "#005b90",
    uw_red: "#cf0a1b",
    uw_gray_lightest: "#f3f3f3",
    irrigate: "#cc2827",
    caution: "#e49e22",
    ok: "#008246",
    full: "#0077c2",
    off: "#e5e7eb"
  }.freeze

  FONT = "'Red Hat Text',-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"
  DISPLAY_FONT = "'Red Hat Display',#{FONT}"

  # Inline styles, since Outlook and Gmail ignore most of a stylesheet
  STYLES = {
    p: "margin:0 0 16px",
    h1: "font-family:#{DISPLAY_FONT};font-size:22px;line-height:1.25;font-weight:700;margin:0 0 4px;color:#{COLORS[:ink]}",
    muted: "color:#{COLORS[:muted]}",
    rule: "border-top:1px solid #{COLORS[:line]}",
    # A card like the app's (rounded-lg border border-line); Outlook leaves the corners square
    card: "border:1px solid #{COLORS[:line]};border-radius:8px;border-collapse:separate;margin:0 0 20px",
    card_header: "background:#{COLORS[:uw_gray_lightest]};border-bottom:1px solid #{COLORS[:line]};" \
      "border-radius:8px 8px 0 0;padding:10px 16px",
    card_body: "padding:4px 16px 12px",
    link: "color:#{COLORS[:brand_dark]};text-decoration:underline"
  }.freeze

  def email_style(*names) = names.map { |name| STYLES.fetch(name) }.join(";")

  # A link in an outgoing email. ses:no-track stops Amazon SES (which the servers' mail relays
  # through) rewriting it into a click-tracking redirect, which ad blockers flag. Written out by
  # hand because AWS documents the bare attribute form.
  def email_link_to(text, url, style: STYLES[:link])
    "<a ses:no-track href=\"#{ERB::Util.h(url)}\" style=\"#{ERB::Util.h(style)}\">#{ERB::Util.h(text)}</a>".html_safe
  end

  # The email's main action as a button: a table cell, which Outlook draws where it wouldn't pad a link
  def email_button(text, url)
    link = email_link_to(text, url, style: "display:inline-block;padding:11px 22px;color:#{COLORS[:white]};" \
      "font-weight:600;text-decoration:none;border-radius:6px")
    tag.table(role: "presentation", cellpadding: 0, cellspacing: 0, border: 0, style: "margin:4px 0 20px") do
      tag.tr { tag.td(link, bgcolor: COLORS[:brand], style: "background:#{COLORS[:brand]};border-radius:6px") }
    end
  end

  # A 600px column centered in a full-width band. Outlook ignores max-width, so it gets a fixed-width
  # table in a conditional comment.
  def email_column(padding: "0", &block)
    tag.table(role: "presentation", width: "100%", cellpadding: 0, cellspacing: 0, border: 0,
      style: "max-width:600px;margin:0 auto") do
      tag.tr { tag.td(capture(&block), style: "padding:#{padding}") }
    end.then do |column|
      safe_join([
        '<!--[if mso]><table role="presentation" width="600" align="center" cellpadding="0" cellspacing="0" border="0"><tr><td><![endif]-->'.html_safe,
        column,
        "<!--[if mso]></td></tr></table><![endif]-->".html_safe
      ])
    end
  end
end

module EmailHelper
  # A link in an outgoing email. ses:no-track stops Amazon SES (which the servers' mail relays
  # through) rewriting it into a click-tracking redirect, which ad blockers flag. Written out by
  # hand because AWS documents the bare attribute form.
  def email_link_to(text, url)
    "<a ses:no-track href=\"#{ERB::Util.h(url)}\">#{ERB::Util.h(text)}</a>".html_safe
  end
end

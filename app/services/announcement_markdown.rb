# An announcement's Markdown as email HTML: CommonMark (with autolinked URLs, strikethrough, and a
# line break wherever the text has one, as people typing an email expect), raw HTML left out, then
# each element given the inline styles mail clients need (EmailHelper::STYLES) and links kept out of
# SES's click tracking (EmailHelper#email_link_to). Placeholders ({{first_name}}) are held aside as
# plain tokens while it's rendered, so Markdown never sees or mangles them, and the block given to
# to_html fills each one (with HTML-escaped text).
class AnnouncementMarkdown
  OPTIONS = {
    parse: {smart: false},
    render: {hardbreaks: true, unsafe: false},
    extension: {
      autolink: true, strikethrough: true, tagfilter: true,
      table: false, tasklist: false, header_ids: nil, footnotes: false, description_lists: false
    }
  }.freeze

  COLORS = EmailHelper::COLORS
  STYLES = {
    "p" => EmailHelper::STYLES[:p],
    "h1" => "#{EmailHelper::STYLES[:h1]};margin:0 0 12px",
    "h2" => "font-family:#{EmailHelper::DISPLAY_FONT};font-size:18px;line-height:1.3;font-weight:700;margin:24px 0 8px;color:#{COLORS[:ink]}",
    "h3" => "font-size:16px;line-height:1.3;font-weight:700;margin:20px 0 6px;color:#{COLORS[:ink]}",
    "ul" => "margin:0 0 16px;padding-left:24px",
    "ol" => "margin:0 0 16px;padding-left:24px",
    "li" => "margin:0 0 4px",
    "a" => EmailHelper::STYLES[:link],
    "blockquote" => "margin:0 0 16px;padding:0 0 0 12px;border-left:3px solid #{COLORS[:line]};color:#{COLORS[:muted]}",
    "hr" => "border:0;border-top:1px solid #{COLORS[:line]};margin:24px 0",
    "code" => "font-family:Consolas,Menlo,monospace;font-size:14px;background:#{COLORS[:uw_gray_lightest]};padding:1px 4px;border-radius:4px",
    "pre" => "margin:0 0 16px;padding:12px;background:#{COLORS[:uw_gray_lightest]};border-radius:6px;white-space:pre-wrap",
    "img" => "max-width:100%;height:auto;border:0"
  }.then { |styles| styles.merge(%w[h4 h5 h6].to_h { |tag| [tag, styles["h3"]] }) }.freeze # h4–h6 look like h3

  TOKEN = /wispph(\d+)x/

  def initialize(markdown)
    @markdown = markdown.to_s
  end

  # The HTML, with each placeholder replaced by the block's result for it (the placeholder's text,
  # escaped, without a block)
  def to_html(&fill)
    fill ||= ->(placeholder) { ERB::Util.html_escape(placeholder) }
    placeholders = []
    source = @markdown.gsub(Announcement::PLACEHOLDER) do
      placeholders << Regexp.last_match(0)
      "wispph#{placeholders.size - 1}x"
    end
    fragment = Nokogiri::HTML5.fragment(Commonmarker.to_html(source, options: OPTIONS))
    fragment.css(STYLES.keys.join(",")).each { |node| style(node) }
    fragment.to_html.gsub('ses:no-track=""', "ses:no-track")
      .gsub(TOKEN) { placeholders[$1.to_i] ? fill.call(placeholders[$1.to_i]) : $& }
      .html_safe
  end

  private

  def style(node)
    styles = STYLES.fetch(node.name).dup
    # Code inside a block keeps the block's background, not its own
    styles = "font-family:Consolas,Menlo,monospace;font-size:14px" if node.name == "code" && node.parent&.name == "pre"
    # The last paragraph or list in a quote has no margin under it, inside the quote's own
    styles += ";margin-bottom:0" if node.parent&.name == "blockquote" && node.next_element.nil?
    node["style"] = styles
    node["ses:no-track"] = "" if node.name == "a"
  end
end

# An email from WISP's admins to an audience of accounts, composed in Markdown with
# placeholders for each recipient ({{first_name}}, {{name|there}}), sent in WISP's email layout
# (AnnouncementMailer). A draft is edited and test-sent; sending freezes its recipients as
# deliveries (AnnouncementDelivery) and AnnouncementJob sends them, so resuming reaches only those
# it missed. Accounts that unsubscribed from announcements (users.announcements) are left out, as
# are unconfirmed ones and reserved addresses (the demo account's).
class Announcement < ApplicationRecord
  AUDIENCES = {
    "all" => {label: "Everyone", description: "Every confirmed account", dated: false},
    "active_since" => {label: "Active since a date", description: "Accounts that used WISP or signed in on or after the date", dated: true},
    "joined_since" => {label: "Joined since a date", description: "Accounts created on or after the date", dated: true},
    "no_farms" => {label: "No farms yet", description: "Accounts none of whose operations has a farm", dated: false}
  }.freeze

  # What a placeholder is replaced with for each recipient; {{key|fallback}} gives the fallback when
  # the value is blank
  PLACEHOLDERS = {
    "first_name" => {description: "First name", value: ->(user) { user.first_name }},
    "last_name" => {description: "Last name", value: ->(user) { user.last_name }},
    "name" => {description: "Full name, or the email address without one", value: ->(user) { user.display_name }},
    "email" => {description: "Email address", value: ->(user) { user.email }}
  }.freeze
  PLACEHOLDER = /\{\{\s*([a-z_]+)\s*(?:\|([^}]*))?\}\}/

  # Example addresses (RFC 2606) never receive mail: they're the demo account's and test accounts'
  RESERVED_DOMAINS = %w[example.com example.org example.net].freeze

  STATUSES = %w[draft sending sent incomplete].freeze
  # A send that hasn't moved in this long has stopped (its worker restarted), so it can be resumed
  STALLED_AFTER = 10.minutes

  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :sent_by, class_name: "User", optional: true
  has_many :deliveries, class_name: "AnnouncementDelivery", dependent: :delete_all

  validates :subject, presence: true, length: {maximum: 200}
  validates :body, presence: true, length: {maximum: 20_000}
  validates :audience, inclusion: {in: AUDIENCES.keys}
  validates :audience_date, presence: true, if: :dated?
  validate :placeholders_known

  # The composer calls the body the message
  def self.human_attribute_name(attribute, options = {})
    (attribute.to_s == "body") ? "Message" : super
  end

  def self.reachable
    User.where.not(confirmed_at: nil).where(announcements: true)
      .where.not("split_part(users.email, '@', 2) ILIKE ANY (ARRAY[?])", RESERVED_DOMAINS)
  end

  # The accounts the audience would reach now
  def self.recipients_for(audience, date = nil)
    users = reachable
    case audience
    when "all" then users
    when "active_since"
      users.where(id: ActivityDay.where(date: date..).select(:user_id))
        .or(users.where(current_sign_in_at: date.beginning_of_day..))
    when "joined_since" then users.where(created_at: date.beginning_of_day..)
    when "no_farms" then users.where.not(id: Membership.joins(group: :farms).select(:user_id))
    else User.none
    end
  end

  def recipients = self.class.recipients_for(audience, audience_date)

  def dated? = AUDIENCES.dig(audience, :dated) || false

  def audience_text
    label = AUDIENCES.dig(audience, :label) || audience
    (dated? && audience_date) ? label.sub("a date", audience_date.strftime("%b %-d, %Y")) : label
  end

  def draft? = status == "draft"

  def sending? = status == "sending"

  def stalled? = sending? && updated_at < STALLED_AFTER.ago

  # Sent with failures, or stopped partway
  def resumable? = status == "incomplete" || stalled?

  # The subject and body for a user: {subject:, html:, text:}
  def render_for(user)
    values = PLACEHOLDERS.transform_values { |placeholder| placeholder[:value].call(user).to_s }
    {
      subject: fill(subject, values),
      html: AnnouncementMarkdown.new(body).to_html { |text| fill(text, values, html: true) },
      text: fill(body, values)
    }
  end

  # Freezes the recipients and starts sending; false unless it's a draft with someone to send to
  def send!(by:)
    started = transaction do
      next false unless self.class.where(id:, status: "draft").update_all(status: "sending", sent_at: Time.current,
        sent_by_id: by.id, updated_at: Time.current) == 1

      ids = recipients.pluck(:id)
      raise ActiveRecord::Rollback if ids.empty?

      now = Time.current
      AnnouncementDelivery.insert_all!(ids.map { |user_id| {announcement_id: id, user_id:, created_at: now, updated_at: now} })
      update_columns(recipients_count: ids.size)
      true
    end
    reload
    AnnouncementJob.perform_later(self) if started
    started || false
  end

  # Sends again to those it failed for or hadn't reached; false unless it's resumable
  def resume!
    return false unless resumable?
    return false unless self.class.where(id:, status: %w[incomplete sending], updated_at: updated_at)
      .update_all(status: "sending", updated_at: Time.current) == 1

    deliveries.where(status: %w[failed sending]).update_all(status: "pending", error: nil, updated_at: Time.current)
    reload
    AnnouncementJob.perform_later(self)
    true
  end

  # {pending:, sent:, failed:, skipped:} for a sent announcement
  def progress
    counts = deliveries.group(:status).count
    {pending: counts.fetch("pending", 0) + counts.fetch("sending", 0), sent: counts.fetch("sent", 0),
     failed: counts.fetch("failed", 0), skipped: counts.fetch("skipped", 0)}
  end

  private

  # Placeholders replaced by the user's values, HTML-escaped for the email's HTML
  def fill(text, values, html: false)
    text.gsub(PLACEHOLDER) do
      value = values.fetch($1, "").presence || $2.to_s.strip
      html ? ERB::Util.html_escape(value) : value
    end
  end

  def placeholders_known
    unknown = [subject, body].compact.flat_map { |text| text.scan(PLACEHOLDER).map(&:first) }.uniq - PLACEHOLDERS.keys
    return if unknown.empty?

    errors.add(:body, "has #{unknown.map { |key| "{{#{key}}}" }.to_sentence} which WISP doesn't know; " \
      "use #{PLACEHOLDERS.keys.map { |key| "{{#{key}}}" }.to_sentence(last_word_connector: " or ")}")
  end
end

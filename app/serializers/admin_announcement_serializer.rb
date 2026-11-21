# An announcement on the admin pages (Admin::AnnouncementsController)
class AdminAnnouncementSerializer < ApplicationSerializer
  typelize_from Announcement

  attributes :id, :subject, :body, :audience, :audience_date, :status, :sent_at, :recipients_count, :created_at

  attribute :audience_text, &:audience_text
  attribute :created_by do |announcement|
    announcement.created_by&.email
  end
  attribute :sent_by do |announcement|
    announcement.sent_by&.email
  end
  attribute :resumable, &:resumable?

  typelize audience: "'all' | 'active_since' | 'joined_since' | 'no_farms'",
    status: "'draft' | 'sending' | 'sent' | 'incomplete'", audience_date: "string | null", sent_at: "string | null",
    recipients_count: "number | null", created_at: :string, audience_text: :string, created_by: "string | null",
    sent_by: "string | null", resumable: :boolean
end

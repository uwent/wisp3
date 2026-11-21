# One recipient of a sent announcement: pending until AnnouncementJob claims it (sending), then sent,
# failed (with the error) or skipped (unsubscribed or unconfirmed since it was sent)
class AnnouncementDelivery < ApplicationRecord
  STATUSES = %w[pending sending sent failed skipped].freeze

  belongs_to :announcement
  belongs_to :user

  # Takes a pending delivery for sending; false if another run already did
  def claim! = self.class.where(id:, status: "pending").update_all(status: "sending", updated_at: Time.current) == 1
end

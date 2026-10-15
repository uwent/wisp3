# An operation (Group), farm, pivot or field a user has left out of their daily digest
class DigestExclusion < ApplicationRecord
  SUBJECT_TYPES = %w[Group Farm Pivot Field].freeze

  belongs_to :user
  belongs_to :subject, polymorphic: true

  validates :subject_type, inclusion: {in: SUBJECT_TYPES}
end

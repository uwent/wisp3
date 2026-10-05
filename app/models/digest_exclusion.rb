# An operation (Group), farm or field a user has left out of their daily digest
class DigestExclusion < ApplicationRecord
  SUBJECT_TYPES = %w[Group Farm Field].freeze

  belongs_to :user
  belongs_to :subject, polymorphic: true

  validates :subject_type, inclusion: {in: SUBJECT_TYPES}
end

class Farm < ApplicationRecord
  belongs_to :group
  # Groups first, so they ungroup their pivots before the pivots go
  has_many :pivot_groups, -> { order(:name) }, dependent: :destroy
  has_many :pivots, -> { order(:name) }, dependent: :destroy
  has_many :fields, through: :pivots
  has_many :digest_exclusions, as: :subject, dependent: :delete_all

  validates :name, presence: true, length: {maximum: 100}

  normalizes :notes, with: ->(text) { text.strip.presence }
end

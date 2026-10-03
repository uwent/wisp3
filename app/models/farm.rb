class Farm < ApplicationRecord
  belongs_to :group
  has_many :pivots, -> { order(:name) }, dependent: :destroy
  has_many :fields, through: :pivots

  validates :name, presence: true, length: {maximum: 100}

  normalizes :notes, with: ->(text) { text.strip.presence }
end

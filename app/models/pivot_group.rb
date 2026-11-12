# Pivots on one farm that share a rain gauge (PLAN.md Phase 8 G.4). Nothing is stored per group per
# day: daily entry fills a group's rain into its pivots' fields, which keep their own entries.
class PivotGroup < ApplicationRecord
  belongs_to :farm
  has_many :pivots, -> { order(:name) }, dependent: :nullify, inverse_of: :pivot_group

  validates :name, presence: true, length: {maximum: 100}

  normalizes :name, with: ->(name) { name.strip }
end

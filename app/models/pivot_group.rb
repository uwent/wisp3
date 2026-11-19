# Pivots on one farm that share a rain gauge (PLAN.md Phase 8 G.4). Nothing is stored per group per
# day: daily entry fills a group's rain into its pivots' fields, which keep their own entries.
class PivotGroup < ApplicationRecord
  belongs_to :farm
  # Who added it, who may delete it as well as the owners (G.15); NULL for those made before
  belongs_to :created_by, class_name: "User", optional: true
  has_many :pivots, -> { order(:name) }, dependent: :nullify, inverse_of: :pivot_group

  validates :name, presence: true, length: {maximum: 100}

  # use_model_precip: the group's rainfall setting (Q7), as it shares a rain gauge; NULL follows its
  # farm's (Pivot#use_model_precip?)

  normalizes :name, with: ->(name) { name.strip }
end

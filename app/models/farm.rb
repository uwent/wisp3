class Farm < ApplicationRecord
  belongs_to :group
  # Groups first, so they ungroup their pivots before the pivots go
  has_many :pivot_groups, -> { order(:name) }, dependent: :destroy
  has_many :pivots, -> { order(:name) }, dependent: :destroy
  has_many :fields, through: :pivots
  has_many :digest_exclusions, as: :subject, dependent: :delete_all

  validates :name, presence: true, length: {maximum: 100}

  # use_model_precip: the farm's rainfall setting (Q7), for its systems in no irrigation group or in
  # one following it (Pivot#use_model_precip?): a farm is a compact area, where rain runs alike

  normalizes :notes, with: ->(text) { text.strip.presence }
end

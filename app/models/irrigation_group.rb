# Systems on one farm that share a rain gauge. Nothing is stored per group per
# day: daily entry fills a group's rain into its systems' fields, which keep their own entries.
class IrrigationGroup < ApplicationRecord
  belongs_to :farm
  # Who added it, who may delete it as well as the owners; NULL for those made before
  belongs_to :created_by, class_name: "User", optional: true
  has_many :systems, -> { order(:name) }, class_name: "IrrigationSystem", dependent: :nullify, inverse_of: :irrigation_group

  validates :name, presence: true, length: {maximum: 100}

  # use_model_precip: the group's rainfall setting (Q7), as it shares a rain gauge; NULL follows its
  # farm's (IrrigationSystem#use_model_precip?)

  normalizes_name :name
end

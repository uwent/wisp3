class Farm < ApplicationRecord
  belongs_to :group
  # Groups first, so they ungroup their systems before the systems go
  has_many :irrigation_groups, -> { order(:name) }, dependent: :destroy
  has_many :systems, -> { order(:name) }, class_name: "IrrigationSystem", dependent: :destroy
  has_many :fields, through: :systems
  has_many :digest_exclusions, as: :subject, dependent: :delete_all

  validates :name, presence: true, length: {maximum: 100}

  # use_model_precip: the farm's rainfall setting (Q7), for its systems in no irrigation group or in
  # one following it (IrrigationSystem#use_model_precip?): a farm is a compact area, where rain runs alike

  normalizes_name :name
  normalizes_text :notes
end

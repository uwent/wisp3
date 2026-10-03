class Farm < ApplicationRecord
  belongs_to :group
  has_many :pivots, dependent: :destroy
  has_many :fields, through: :pivots

  validates :name, presence: true, length: {maximum: 100}
end

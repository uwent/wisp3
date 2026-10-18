# A soil texture's default water-holding fractions (reference data, db/reference/soil_types.yml)
class SoilType < ApplicationRecord
  DEFAULT_KEY = "sandy_loam"

  has_many :fields, dependent: :restrict_with_exception

  validates :key, :name, presence: true
  validates :key, uniqueness: true
  validates :field_capacity, :perm_wilting_pt, numericality: {greater_than: 0, less_than: 0.6}

  def self.default = find_by!(key: DEFAULT_KEY)

  # Where each soil type's values come from (the reference file's basis), for the About page
  def self.bases
    @bases ||= YAML.load_file(Rails.root.join("db/reference/soil_types.yml")).to_h { |row| [row["key"], row["basis"]] }
  end
end

# A generic canopy curve a crop without its own can follow (PLAN.md Phase 8 G.3), for the planting form
class GenericCurveSerializer < ApplicationSerializer
  attributes :key, :name, :basis, :season_days
  typelize key: :string, name: :string, basis: :string, season_days: "number | null"

  # Every generic curve, in the file's order
  def self.all = new(CanopyCurve.generic.values).to_h
end

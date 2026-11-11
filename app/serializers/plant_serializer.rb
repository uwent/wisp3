class PlantSerializer < ApplicationSerializer
  attributes :id, :key, :name, :default_max_root_zone_depth

  # Whether the crop has an LAI curve (only those can use LAI) and a percent cover curve (PLAN.md Phase 6.7)
  attribute(:has_lai_curve) { |plant| !plant.canopy_model.nil? }
  attribute(:has_cover_curve) { |plant| CanopyCurve.for(plant.key).present? }
  # Whether its plantings take a vine kill date (potato)
  attribute(:has_vine_kill) { |plant| CanopyCurve.for(plant.key)&.vine_kill? || false }
  # Typical days from emergence to harvest, which suggests a harvest date (PLAN.md Phase 8 G.2)
  attribute(:season_days) { |plant| CanopyCurve.for(plant.key)&.season_days }
  typelize has_lai_curve: :boolean, has_cover_curve: :boolean, has_vine_kill: :boolean, season_days: "number | null"
end

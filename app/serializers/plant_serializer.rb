class PlantSerializer < ApplicationSerializer
  attributes :id, :key, :name, :default_max_root_zone_depth

  # Whether the crop has an LAI curve (only those can use LAI) and a percent cover curve (PLAN.md Phase 6.7)
  attribute(:has_lai_curve) { |plant| !plant.canopy_model.nil? }
  attribute(:has_cover_curve) { |plant| CanopyCurve.for(plant.key).present? }
  typelize has_lai_curve: :boolean, has_cover_curve: :boolean
end

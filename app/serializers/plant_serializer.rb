class PlantSerializer < ApplicationSerializer
  attributes :id, :key, :name, :default_max_root_zone_depth

  # Whether LAI works without entered readings (PLAN.md §5.3)
  attribute :has_canopy_curve do |plant|
    !plant.canopy_model.nil?
  end
  typelize has_canopy_curve: :boolean
end

class PlantingSerializer < ApplicationSerializer
  attributes :id, :field_id, :plant_id, :variety, :season_start, :emergence_date, :end_date, :max_root_zone_depth,
    :mad_frac, :et_method, :target_ad_pct, :initial_moisture_pct, :notes

  attribute :plant_name do |planting|
    planting.plant.name
  end

  attribute :plant_key do |planting|
    planting.plant.key
  end

  # Whether the plant has an LAI growth curve (CanopyModel) for LAI plantings without readings
  attribute :canopy_curve do |planting|
    planting.plant.canopy_model.present?
  end

  attribute :year do |planting|
    planting.season_year
  end
  typelize plant_name: :string, plant_key: :string, canopy_curve: :boolean, year: :number,
    et_method: "'pct_cover' | 'lai'"
end

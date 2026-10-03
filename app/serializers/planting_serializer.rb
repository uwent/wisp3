class PlantingSerializer < ApplicationSerializer
  attributes :id, :field_id, :plant_id, :variety, :season_start, :emergence_date, :end_date, :max_root_zone_depth,
    :mad_frac, :et_method, :target_ad_pct, :initial_moisture_pct, :notes

  attribute :plant_name do |planting|
    planting.plant.name
  end

  attribute :year do |planting|
    planting.season_year
  end
  typelize plant_name: :string, year: :number, et_method: "'pct_cover' | 'lai'"
end

class PlantingSerializer < ApplicationSerializer
  attributes :id, :field_id, :plant_id, :variety, :season_start, :emergence_date, :end_date, :vine_kill_date,
    :max_root_zone_depth, :mad_frac, :et_method, :canopy_interpolation, :target_ad_pct, :initial_moisture_pct, :notes

  attribute :plant_name do |planting|
    planting.plant.name
  end

  attribute :plant_key do |planting|
    planting.plant.key
  end

  # Whether the crop has a canopy curve for the planting's method, and how readings combine with it
  attribute(:canopy_curve, &:canopy_curve?)
  attribute(:effective_canopy_interpolation, &:effective_canopy_interpolation)
  # Whether the crop takes a vine kill date (potato)
  attribute(:vine_kill_crop, &:vine_kill_crop?)

  attribute :year do |planting|
    planting.season_year
  end
  typelize plant_name: :string, plant_key: :string, canopy_curve: :boolean, vine_kill_crop: :boolean, year: :number,
    canopy_interpolation: "'linear' | 'curve' | null", effective_canopy_interpolation: "'linear' | 'curve'",
    et_method: "'pct_cover' | 'lai'"
end

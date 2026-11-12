class PlantingSerializer < ApplicationSerializer
  attributes :id, :field_id, :plant_id, :variety, :season_start, :emergence_date, :end_date, :vine_kill_date,
    :max_root_zone_depth, :mad_frac, :et_method, :canopy_interpolation, :target_ad_pct, :initial_moisture_pct, :notes,
    # The values the season runs on, copied from the field (PLAN.md Phase 8 G.9)
    :soil_type_id, :field_capacity, :perm_wilting_pt, :area_acres,
    # Whole field, or part of it: a plot (length × width, ft) or acres (G.11)
    :partial, :plot_length_ft, :plot_width_ft,
    # A plot on its own soil, which the field's soil edits leave alone
    :own_soil,
    # A crop without its own curve: the generic one picked, or none (readings only); null its default (G.3)
    :canopy_curve_key

  attribute :plant_name do |planting|
    planting.plant.name
  end

  attribute :plant_key do |planting|
    planting.plant.key
  end

  # On the perennial regrowth curve, so it can be cut; and its cuttings (G.3)
  attribute(:takes_cuttings) { |planting| planting.cover_curve&.key == CanopyCutting::CURVE && planting.et_method == "pct_cover" }
  attribute(:cuttings) { |planting| planting.canopy_cuttings.map { |cutting| {id: cutting.id, date: cutting.date} } }
  typelize takes_cuttings: :boolean, cuttings: "{ id: number; date: string }[]"

  # The generic curve in effect, for a crop without its own ("Vegetable, medium"), or null
  attribute(:generic_curve_name) { |planting| planting.generic_curve_crop? ? planting.cover_curve&.name : nil }
  typelize generic_curve_name: "string | null", canopy_curve_key: "string | null"

  # Whether the crop has a canopy curve for the planting's method, and how readings combine with it
  attribute(:canopy_curve, &:canopy_curve?)
  attribute(:effective_canopy_interpolation, &:effective_canopy_interpolation)
  # The crop's typical days from emergence to harvest, for "End the season" (PLAN.md Phase 8 G.2)
  attribute(:season_days, &:season_days)
  # Whether the crop takes a vine kill date (potato)
  attribute(:vine_kill_crop, &:vine_kill_crop?)

  attribute :year do |planting|
    planting.season_year
  end

  # An ended season keeps its own soil and area; one still running follows its field's
  attribute(:ended) { |planting| planting.ended? }
  # Part-field plantings on the field at once add up to more than its area (a warning)
  attribute(:exceeds_field_area) { |planting| planting.exceeds_field_area? }
  typelize season_days: "number | null", ended: :boolean, exceeds_field_area: :boolean, plant_name: :string, plant_key: :string, canopy_curve: :boolean, vine_kill_crop: :boolean, year: :number,
    canopy_interpolation: "'linear' | 'curve' | null", effective_canopy_interpolation: "'linear' | 'curve'",
    et_method: "'pct_cover' | 'lai'"
end

FactoryBot.define do
  factory :plant do
    sequence(:key) { |n| "crop_#{n}" }
    name { "Potato" }
    default_max_root_zone_depth { 16.0 }
    # Kc 1.0: crop ET is the percent cover table's, so specs' hand-worked numbers hold (C21's own
    # specs set a crop's Kc)
    kc_mid { 1.0 }
    crop_height_m { 0.6 }

    trait :field_corn do
      key { "field_corn" }
      name { "Field Corn" }
      default_max_root_zone_depth { 33.0 }
      canopy_model { "field_corn" }
      kc_mid { 1.2 }
      crop_height_m { 2.0 }
    end

    # FAO-56's basal coefficients, so the balance runs the dual crop coefficient and water stress (C22, C26)
    trait :dual do
      kcb_mid { 1.05 }
      kcb_end { 0.5 }
    end
  end

  factory :soil_type do
    sequence(:key) { |n| "soil_#{n}" }
    name { "Sandy Loam" }
    field_capacity { 0.15 }
    perm_wilting_pt { 0.05 }
  end

  factory :farm do
    group
    sequence(:name) { |n| "Farm #{n}" }
  end

  factory :pivot do
    farm
    sequence(:name) { |n| "Pivot #{n}" }
    latitude { 44.12 }
    longitude { -89.53 }
  end

  factory :pivot_group do
    farm
    sequence(:name) { |n| "Gauge #{n}" }
  end

  factory :field do
    pivot
    soil_type
    sequence(:name) { |n| "Field #{n}" }
    area_acres { 60.0 }
  end

  factory :planting do
    field
    plant
    season_start { Date.new(2026, 4, 1) }
    emergence_date { Date.new(2026, 5, 15) }
    end_date { Date.new(2026, 9, 30) }
    max_root_zone_depth { 24.0 }
    mad_frac { 0.5 }
    et_method { "pct_cover" }
  end

  factory :canopy_observation do
    planting
    date { Date.new(2026, 6, 15) }
    pct_cover { 50.0 }
  end

  factory :field_entry do
    field
    date { Date.new(2026, 6, 1) }
  end
end

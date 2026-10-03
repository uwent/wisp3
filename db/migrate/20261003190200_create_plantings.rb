class CreatePlantings < ActiveRecord::Migration[8.1]
  def change
    enable_extension "btree_gist" # for the no-overlap exclusion constraint

    # One crop on one field for one season (replaces legacy crops + Field#current_crop, C10)
    create_table :plantings do |t|
      t.references :field, null: false, foreign_key: true
      t.references :plant, null: false, foreign_key: true
      t.string :variety
      t.date :season_start, null: false # the water balance starts here, at initial_moisture_pct
      t.date :emergence_date, null: false
      t.date :end_date, null: false # harvest or kill; the balance stops here
      t.float :max_root_zone_depth, null: false # inches
      t.float :mad_frac, null: false
      t.string :et_method, null: false, default: "pct_cover"
      t.float :target_ad_pct
      t.float :initial_moisture_pct # NULL = start at field capacity
      t.text :notes
      t.timestamps

      # Emergence can precede season_start (perennials such as alfalfa, winter wheat)
      t.check_constraint "season_start <= end_date AND emergence_date <= end_date", name: "plantings_date_order"
      t.check_constraint "max_root_zone_depth > 0", name: "plantings_mrzd_positive"
      t.check_constraint "mad_frac BETWEEN 0.05 AND 0.95", name: "plantings_mad_frac_range"
      t.check_constraint "et_method IN ('pct_cover', 'lai')", name: "plantings_et_method"
      t.check_constraint "target_ad_pct IS NULL OR target_ad_pct BETWEEN 0 AND 100", name: "plantings_target_range"
      t.check_constraint "initial_moisture_pct IS NULL OR initial_moisture_pct BETWEEN 0 AND 100", name: "plantings_initial_moisture_range"
      t.exclusion_constraint "field_id WITH =, daterange(season_start, end_date, '[]') WITH &&",
        using: :gist, name: "plantings_no_overlap"
    end

    # Canopy readings: anchor points for interpolation (Canopy)
    create_table :canopy_observations do |t|
      t.references :planting, null: false, foreign_key: true, index: false
      t.date :date, null: false
      t.float :pct_cover
      t.float :lai
      t.timestamps
      t.index [:planting_id, :date], unique: true
      t.check_constraint "num_nonnulls(pct_cover, lai) = 1", name: "canopy_observations_one_value"
      t.check_constraint "pct_cover IS NULL OR pct_cover BETWEEN 0 AND 100", name: "canopy_observations_pct_cover_range"
      t.check_constraint "lai IS NULL OR lai >= 0", name: "canopy_observations_lai_positive"
    end
  end
end

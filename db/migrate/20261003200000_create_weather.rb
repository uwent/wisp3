class CreateWeather < ActiveRecord::Migration[8.1]
  # Daily weather values, stored in WISP's units (inches, °F, mph); soil moisture as a volume
  # fraction (m³/m³), comparable with field capacity. NULL = missing, never 0.
  def daily_columns(t)
    t.float :et0_in
    t.float :precip_in
    t.float :rain_in
    t.float :snowfall_in
    t.float :snow_depth_in # daily max
    t.float :tmax_f
    t.float :tmin_f
    t.float :tmean_f
    t.float :dew_point_f # daily mean
    t.float :rh_mean_pct
    t.float :rh_min_pct
    t.float :rh_max_pct
    t.float :vpd_max_kpa
    t.float :pressure_msl_hpa
    t.float :wind_speed_mph # daily mean
    t.float :wind_speed_max_mph
    t.float :wind_gust_max_mph
    t.float :wind_direction_deg # vector mean
    t.float :cloud_cover_pct
    t.float :cloud_cover_low_pct
    t.float :cloud_cover_mid_pct
    t.float :cloud_cover_high_pct
    t.float :soil_temp_0_7cm_f
    t.float :soil_temp_7_28cm_f
    t.float :soil_temp_28_100cm_f
    t.float :soil_temp_100_255cm_f
    t.float :soil_moisture_0_7cm
    t.float :soil_moisture_7_28cm
    t.float :soil_moisture_28_100cm
    t.float :soil_moisture_100_255cm
  end

  def change
    # One ECMWF IFS O1280 grid cell (~9 km); pivots in a cell share its weather
    create_table :weather_cells do |t|
      t.float :latitude, null: false # cell center, where requests are made
      t.float :longitude, null: false
      t.string :timezone # from Open-Meteo; daily values are local days
      t.float :elevation_m
      t.datetime :last_fetched_at
      t.text :last_error
      t.datetime :last_error_at
      t.timestamps
      t.index [:latitude, :longitude], unique: true
    end

    add_reference :pivots, :weather_cell, foreign_key: true

    # Past days from the model (provisional until final, then never overwritten)
    create_table :weather_days do |t|
      t.references :weather_cell, null: false, foreign_key: true, index: false
      t.date :date, null: false
      daily_columns(t)
      t.string :model, null: false
      t.string :soil_model
      t.integer :hours, null: false # hourly values the day was built from
      t.boolean :final, null: false, default: false
      t.datetime :fetched_at, null: false
      t.timestamps
      t.index [:weather_cell_id, :date], unique: true
    end

    # One forecast issue for a cell: payload {"days" => [{"date" => …, <daily columns>}, …]}
    create_table :weather_forecasts do |t|
      t.references :weather_cell, null: false, foreign_key: true, index: false
      t.datetime :issued_at, null: false
      t.string :model, null: false
      t.string :kind, null: false, default: "deterministic"
      t.jsonb :payload, null: false
      t.timestamps
      t.index [:weather_cell_id, :issued_at]
      t.check_constraint "kind IN ('deterministic', 'ensemble')", name: "weather_forecasts_kind"
    end
  end
end

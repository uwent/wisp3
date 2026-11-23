# Daily temperature normals per weather cell, for crop canopy curves in thermal time
# (C23): the mean high and low for each day of the year over about 20 recent years of Open-Meteo's
# historical archive (ERA5), fetched once per cell (WeatherNormalsJob). day_of_year counts as in a
# leap year (Feb 29 is 60, Mar 1 always 61).
class CreateWeatherNormals < ActiveRecord::Migration[8.1]
  def change
    create_table :weather_normals do |t|
      t.references :weather_cell, null: false, foreign_key: true, index: false
      t.integer :day_of_year, null: false
      t.float :tmax_f, null: false
      t.float :tmin_f, null: false
      t.integer :first_year, null: false
      t.integer :last_year, null: false
      t.string :model, null: false
      t.datetime :fetched_at, null: false
      t.timestamps
    end
    add_index :weather_normals, [:weather_cell_id, :day_of_year], unique: true
  end
end

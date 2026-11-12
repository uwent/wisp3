# The day's most severe WMO weather code (Open-Meteo's weather_code, highest hour), for the
# forecast's sky icons (G.12)
class AddWeatherCodeToWeatherDays < ActiveRecord::Migration[8.1]
  def change
    add_column :weather_days, :weather_code, :integer
  end
end

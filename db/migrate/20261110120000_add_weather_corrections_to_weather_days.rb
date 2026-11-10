# Weather corrections (PLAN.md D12, §8.5): et0_in becomes WISP's FAO-56 ET0 from corrected
# shortwave, dew_point_f and rh_*_pct the corrected humidity; the values before are kept beside
# them, and each day lists the corrections it went through. Days stored before this have none
# listed until they're refetched (weather:recorrect).
class AddWeatherCorrectionsToWeatherDays < ActiveRecord::Migration[8.1]
  def change
    change_table :weather_days, bulk: true do |t|
      t.float :et0_openmeteo_in
      t.float :shortwave_mj
      t.float :shortwave_raw_mj
      t.float :dew_point_raw_f
      t.float :rh_mean_raw_pct
      t.float :rh_min_raw_pct
      t.float :rh_max_raw_pct
      t.jsonb :corrections, null: false, default: []
    end
  end
end

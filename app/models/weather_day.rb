# A cell's weather for one local day, built from hourly model values (Weather::Daily). Provisional
# days are refreshed as the model revises them; final days (WeatherFinalizeJob) are not.
class WeatherDay < ApplicationRecord
  VALUE_COLUMNS = %w[
    et0_in precip_in rain_in snowfall_in snow_depth_in tmax_f tmin_f tmean_f dew_point_f
    rh_mean_pct rh_min_pct rh_max_pct vpd_max_kpa pressure_msl_hpa wind_speed_mph wind_speed_max_mph
    wind_gust_max_mph wind_direction_deg cloud_cover_pct cloud_cover_low_pct cloud_cover_mid_pct
    cloud_cover_high_pct soil_temp_0_7cm_f soil_temp_7_28cm_f soil_temp_28_100cm_f soil_temp_100_255cm_f
    soil_moisture_0_7cm soil_moisture_7_28cm soil_moisture_28_100cm soil_moisture_100_255cm
  ].freeze

  belongs_to :weather_cell

  validates :date, :model, :hours, :fetched_at, presence: true

  def degree_days = Weather::DegreeDays.daily(tmax_f, tmin_f)

  # {date => {et0:, precip:}} for the water balance (DailyInputs); dates without a day are absent
  def self.balance_inputs(cell, dates)
    return {} unless cell
    where(weather_cell: cell, date: dates).pluck(:date, :et0_in, :precip_in)
      .to_h { |date, et0, precip| [date, {et0:, precip:}] }
  end
end

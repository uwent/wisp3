# A cell's normal high and low for one day of the year (Weather::Normals), for the days a canopy
# curve in thermal time has no stored or forecast weather: beyond the forecast, and any day missing
# in the past (ThermalTime). day_of_year counts as in a leap year (Feb 29 is 60, Mar 1 always 61).
class WeatherNormal < ApplicationRecord
  belongs_to :weather_cell

  validates :day_of_year, inclusion: {in: 1..366}
  validates :tmax_f, :tmin_f, :first_year, :last_year, :model, :fetched_at, presence: true

  def self.day_of_year(date) = Date.new(2000, date.month, date.day).yday

  # {cell_id => {day_of_year => [tmax_f, tmin_f]}} for the cells that have normals, in one query
  def self.by_cell(cell_ids)
    where(weather_cell_id: cell_ids).pluck(:weather_cell_id, :day_of_year, :tmax_f, :tmin_f).group_by(&:first)
      .transform_values { |rows| rows.to_h { |_, day, tmax, tmin| [day, [tmax, tmin]] } }
  end
end

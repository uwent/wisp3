class Pivot < ApplicationRecord
  # The US and Canada for now (Hawaii to the Arctic, Alaska to Newfoundland). Open-Meteo is
  # global, so this can widen; it also catches swapped or unsigned coordinates.
  LATITUDES = 18.0..84.0
  LONGITUDES = -180.0..-52.0

  belongs_to :farm
  belongs_to :weather_cell, optional: true
  has_many :fields, -> { order(:name) }, dependent: :destroy
  has_many :pivot_irrigations, dependent: :destroy

  validates :name, presence: true, length: {maximum: 100}
  validates :latitude, presence: true, numericality: {in: LATITUDES, message: "must be in the US or Canada"}
  validates :longitude, presence: true, numericality: {in: LONGITUDES, message: "must be in the US or Canada"}
  validates :radius_ft, :pump_capacity_gpm, numericality: {greater_than: 0}, allow_nil: true
  validates :arc_start_deg, :arc_end_deg, numericality: {in: 0..360, message: "must be between 0 and 360"}, allow_nil: true
  validate :arc_complete

  normalizes :equipment, :notes, with: ->(text) { text.strip.presence }

  before_save :assign_weather_cell, if: -> { will_save_change_to_latitude? || will_save_change_to_longitude? }
  after_commit :update_weather, if: -> { saved_change_to_weather_cell_id? && weather_cell_id }

  private

  def assign_weather_cell
    self.weather_cell = WeatherCell.for(latitude, longitude)
  end

  # A new or moved pivot gets its cell's forecast and season-to-date weather in the background
  def update_weather
    WeatherUpdateJob.perform_later(weather_cell_id)
  end

  def arc_complete
    errors.add(:arc_end_deg, "is needed with a start angle") if arc_start_deg && !arc_end_deg
    errors.add(:arc_start_deg, "is needed with an end angle") if arc_end_deg && !arc_start_deg
  end
end

class Pivot < ApplicationRecord
  # The US and Canada for now (Hawaii to the Arctic, Alaska to Newfoundland). Open-Meteo is
  # global, so this can widen; it also catches swapped or unsigned coordinates.
  LATITUDES = 18.0..84.0
  LONGITUDES = -180.0..-52.0

  # A center pivot is a circle (or an arc of one) around its location; a linear move is a machine
  # length_ft long traveling travel_ft along travel_bearing_deg (whole degrees from north, 0–179, as
  # it runs both ways), a rectangle centered on its location.
  KINDS = %w[center linear].freeze
  # The longest center pivots sold are about 2,900 ft (Reinke); the longest linear machines about
  # 3,200 ft (Valley), and travel of more than a mile is beyond what we model. Mirrored in lib/geo.ts.
  MAX_RADIUS_FT = 3000
  MAX_LINEAR_LENGTH_FT = 3300
  MAX_LINEAR_TRAVEL_FT = 5280

  belongs_to :farm
  belongs_to :weather_cell, optional: true
  has_many :digest_exclusions, as: :subject, dependent: :delete_all
  has_many :fields, -> { order(:name) }, dependent: :destroy
  has_many :pivot_irrigations, dependent: :destroy

  validates :name, presence: true, length: {maximum: 100}
  validates :latitude, presence: true, numericality: {in: LATITUDES, message: "must be in the US or Canada"}
  validates :longitude, presence: true, numericality: {in: LONGITUDES, message: "must be in the US or Canada"}
  validates :kind, inclusion: {in: KINDS}
  validates :pump_capacity_gpm, numericality: {greater_than: 0}, allow_nil: true
  validates :radius_ft, numericality: {greater_than: 0}, allow_nil: true
  validates :radius_ft, numericality: {less_than_or_equal_to: MAX_RADIUS_FT,
                                       message: "is longer than any center pivot (at most 3,000 ft, 914 m)"}, allow_nil: true
  with_options if: :linear? do
    validates :length_ft, presence: true, numericality: {greater_than: 0}
    validates :length_ft, numericality: {less_than_or_equal_to: MAX_LINEAR_LENGTH_FT,
                                         message: "is longer than any linear machine (at most 3,300 ft, 1,006 m)"}
    validates :travel_ft, presence: true, numericality: {greater_than: 0}
    validates :travel_ft, numericality: {less_than_or_equal_to: MAX_LINEAR_TRAVEL_FT,
                                         message: "is farther than WISP can model (at most a mile, 1,609 m)"}
    validates :travel_bearing_deg, presence: true, numericality: {only_integer: true, in: 0..179,
                                                                  message: "must be a whole number of degrees from 0 to 179"}
  end
  validates :arc_start_deg, :arc_end_deg, numericality: {in: 0..360, message: "must be between 0 and 360"}, allow_nil: true
  validate :arc_complete

  normalizes :equipment, :notes, with: ->(text) { text.strip.presence }

  before_validation :clear_other_shape

  before_save :assign_weather_cell, if: -> { will_save_change_to_latitude? || will_save_change_to_longitude? }
  after_commit :update_weather, if: -> { saved_change_to_weather_cell_id? && weather_cell_id }

  def linear? = kind == "linear"

  private

  # Only the kind's own dimensions are kept, so switching kinds leaves no stale shape behind
  def clear_other_shape
    if linear?
      self.radius_ft = self.arc_start_deg = self.arc_end_deg = nil
    else
      self.length_ft = self.travel_ft = self.travel_bearing_deg = nil
    end
  end

  def assign_weather_cell
    self.weather_cell = WeatherCell.for(latitude, longitude)
  end

  # A new or moved pivot gets its cell's forecast and season-to-date weather in the background
  def update_weather
    WeatherUpdateJob.perform_later(weather_cell_id)
  end

  def arc_complete
    errors.add(:arc_end_deg, "is needed when a start angle is set") if arc_start_deg && !arc_end_deg
    errors.add(:arc_start_deg, "is needed when an end angle is set") if arc_end_deg && !arc_start_deg
  end
end

class Pivot < ApplicationRecord
  # The US and Canada for now (Hawaii to the Arctic, Alaska to Newfoundland). Open-Meteo is
  # global, so this can widen; it also catches swapped or unsigned coordinates.
  LATITUDES = 18.0..84.0
  LONGITUDES = -180.0..-52.0

  # A pivot in code is any irrigation system (PLAN.md Phase 8 G.5); growers see its kind's name.
  # A center pivot is a circle (or an arc of one) around its location; a linear is a machine
  # length_ft long traveling travel_ft along travel_bearing_deg (whole degrees from north, 0–179, as
  # it runs both ways), a rectangle centered on its location. The other kinds are a point with no
  # dimensions: the place watered one way, whose area comes from its fields (a traveler is set up at
  # each field it waters, its machine named in equipment). Mirrored in lib/geo.ts.
  KIND_NAMES = {"center" => "Pivot", "linear" => "Linear", "traveler" => "Traveler", "solid_set" => "Solid set",
                "drip" => "Drip", "point" => "Location"}.freeze
  KINDS = KIND_NAMES.keys.freeze
  POINT_KINDS = %w[traveler solid_set drip point].freeze
  # The longest center pivots sold are about 2,900 ft (Reinke); the longest linear machines about
  # 3,200 ft (Valley), and travel of more than a mile is beyond what we model. Mirrored in lib/geo.ts.
  MAX_RADIUS_FT = 3000
  MAX_LINEAR_LENGTH_FT = 3300
  MAX_LINEAR_TRAVEL_FT = 5280

  belongs_to :farm
  belongs_to :pivot_group, optional: true
  belongs_to :weather_cell, optional: true
  has_many :digest_exclusions, as: :subject, dependent: :delete_all
  has_many :fields, -> { order(:name) }, dependent: :destroy
  has_many :pivot_irrigations, dependent: :destroy
  # The plantings whose seasons ran on this system (G.14 part 7): its fields' and, for seasons that
  # ended before their field moved to another system, theirs
  has_many :plantings, dependent: nil
  # Its own fields' plantings go with them; seasons that ran here on fields since moved elsewhere
  # are handed to their field's system, as this one's irrigation goes too
  before_destroy :hand_over_plantings

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
  validate :pivot_group_on_farm

  normalizes :equipment, :notes, with: ->(text) { text.strip.presence }

  before_validation :clear_other_shape
  # A pivot moved to another farm leaves its group (groups don't span farms)
  before_validation -> { self.pivot_group = nil }, if: -> { persisted? && farm_id_changed? && pivot_group&.farm_id != farm_id }

  before_save :assign_weather_cell, if: -> { will_save_change_to_latitude? || will_save_change_to_longitude? }
  after_commit :update_weather, if: -> { saved_change_to_weather_cell_id? && weather_cell_id }
  # Plantings that haven't ended move with the pivot; ended ones keep the weather they ran on (G.9)
  after_update :move_open_plantings, if: :saved_change_to_weather_cell_id?

  def linear? = kind == "linear"

  def point? = POINT_KINDS.include?(kind)

  # What growers call it: "Pivot", "Traveler", "Location"
  def kind_name = KIND_NAMES.fetch(kind, "Irrigation system")

  # How a system is named to growers (G.14): "East gun (traveler)", or the name alone when it
  # already says its kind ("Home pivot"). Mirrored by systemName in lib/geo.ts; pages put
  # "Irrigation system:" (or "System:" where space is short) before it, never the kind.
  def label = name.downcase.include?(kind_name.downcase) ? name : "#{name} (#{kind_name.downcase})"

  # The fields this system watered on date (Field#pivot_id_on): those whose planting then ran on it,
  # and its own fields with nothing planted. Its fields today, apart from a field since moved here
  # whose earlier season was elsewhere, or one moved away whose season ran here.
  def fields_on(date)
    Field.where(pivot_id: id).or(Field.where(id: plantings.on(date).select(:field_id)))
      .includes(:plantings).order(:name).select { |field| field.pivot_id_on(date) == id }
  end

  # Every field that is or was on this system, for working out fields_on in the browser
  # (fieldsOn in lib/irrigation.ts): whether it's on it now, and its seasons in the order
  # Field#planting_on picks them, each saying whether it ran here
  def field_seasons
    Field.where(pivot_id: id).or(Field.where(id: plantings.select(:field_id))).includes(:plantings).order(:name)
      .map do |field|
        seasons = field.plantings.sort_by { |planting| [planting.partial? ? 1 : 0, planting.season_start, planting.id] }
        {id: field.id, name: field.name, here: field.pivot_id == id,
         seasons: seasons.map { |planting| {from: planting.season_start, to: planting.end_date, here: planting.pivot_id == id} }}
      end
  end

  private

  # Only the kind's own dimensions are kept, so switching kinds leaves no stale shape behind
  def clear_other_shape
    self.radius_ft = self.arc_start_deg = self.arc_end_deg = nil unless kind == "center"
    self.length_ft = self.travel_ft = self.travel_bearing_deg = nil unless linear?
  end

  def move_open_plantings
    plantings.open.update_all(weather_cell_id:)
  end

  def hand_over_plantings
    plantings.where.not(field_id: fields.select(:id))
      .update_all("pivot_id = (SELECT fields.pivot_id FROM fields WHERE fields.id = plantings.field_id)")
  end

  def assign_weather_cell
    self.weather_cell = WeatherCell.for(latitude, longitude)
  end

  # A new or moved pivot gets its cell's forecast and season-to-date weather in the background
  def update_weather
    WeatherUpdateJob.perform_later(weather_cell_id)
  end

  def pivot_group_on_farm
    errors.add(:pivot_group, "must be on the same farm") if pivot_group && pivot_group.farm_id != farm_id
  end

  def arc_complete
    errors.add(:arc_end_deg, "is needed when a start angle is set") if arc_start_deg && !arc_end_deg
    errors.add(:arc_start_deg, "is needed when an end angle is set") if arc_end_deg && !arc_start_deg
  end
end

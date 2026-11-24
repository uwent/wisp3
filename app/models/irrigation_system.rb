class IrrigationSystem < ApplicationRecord
  # The US and Canada for now (Hawaii to the Arctic, Alaska to Newfoundland). Open-Meteo is
  # global, so this can widen; it also catches swapped or unsigned coordinates.
  LATITUDES = 18.0..84.0
  LONGITUDES = -180.0..-52.0

  # A system in code is any irrigation system; growers see its kind's name.
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
  # The kinds with a percent timer: the end tower (a linear's drive) runs
  # that share of each minute, so a circle or pass puts on inches_at_100 × 100 ÷ percent (the
  # irrigation calculator, percentInches in lib/irrigation.ts)
  TIMER_KINDS = %w[center linear].freeze
  # A circle at 100% puts on a few tenths of an inch; more than 3 is a typo or another unit
  MAX_INCHES_AT_100 = 3.0

  belongs_to :farm
  belongs_to :irrigation_group, optional: true
  belongs_to :weather_cell, optional: true
  has_many :digest_exclusions, as: :subject, dependent: :delete_all
  has_many :fields, -> { order(:name) }, foreign_key: :system_id, inverse_of: :system, dependent: :destroy
  # The plantings whose seasons ran on this system: its fields' and, for seasons that
  # ended before their field moved to another system, theirs
  has_many :plantings, foreign_key: :system_id, inverse_of: :system, dependent: nil
  # Its own fields' plantings go with them; seasons that ran here on fields since moved elsewhere
  # are handed to their field's system
  before_destroy :hand_over_plantings

  validates :name, presence: true, length: {maximum: 100}

  # Whether the balance takes modeled rain on days without entered rain (Q7): its irrigation group's
  # setting, else its farm's. Either way the projection uses forecast rain (DailyInputs).
  def use_model_precip?
    own = irrigation_group&.use_model_precip
    own.nil? ? farm.use_model_precip : own
  end
  validates :latitude, presence: true, numericality: {in: LATITUDES, message: "must be in the US or Canada"}
  validates :longitude, presence: true, numericality: {in: LONGITUDES, message: "must be in the US or Canada"}
  validates :kind, inclusion: {in: KINDS}
  validates :pump_capacity_gpm, numericality: {greater_than: 0}, allow_nil: true
  validates :inches_at_100, numericality: {greater_than: 0, less_than_or_equal_to: MAX_INCHES_AT_100,
                                           message: "must be more than 0 and at most 3 inches (76 mm)"}, allow_nil: true
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
  validate :irrigation_group_on_farm

  normalizes :equipment, :notes, with: ->(text) { text.strip.presence }

  before_validation :clear_other_shape
  # A system moved to another farm leaves its group (groups don't span farms)
  before_validation -> { self.irrigation_group = nil }, if: -> { persisted? && farm_id_changed? && irrigation_group&.farm_id != farm_id }

  before_save :assign_weather_cell, if: -> { will_save_change_to_latitude? || will_save_change_to_longitude? }
  after_commit :update_weather, if: -> { saved_change_to_weather_cell_id? && weather_cell_id }
  # Plantings that haven't ended move with the system; ended ones keep the weather they ran on
  after_update :move_open_plantings, if: :saved_change_to_weather_cell_id?

  def linear? = kind == "linear"

  # What growers call it: "Pivot", "Traveler", "Location"
  def kind_name = KIND_NAMES.fetch(kind, "Irrigation system")

  # How a system is named to growers: "East gun (traveler)", or the name alone when it
  # already says its kind ("Home pivot"). Mirrored by systemName in lib/geo.ts; pages put
  # "Irrigation system:" (or "System:" where space is short) before it, never the kind.
  def label = name.downcase.include?(kind_name.downcase) ? name : "#{name} (#{kind_name.downcase})"

  # The fields this system watered on date (Field#system_id_on): those whose planting then ran on it,
  # and its own fields with nothing planted. Its fields today, apart from a field since moved here
  # whose earlier season was elsewhere, or one moved away whose season ran here.
  def fields_on(date)
    Field.where(system_id: id).or(Field.where(id: plantings.on(date).select(:field_id)))
      .includes(:plantings).order(:name).select { |field| field.system_id_on(date) == id }
  end

  # The irrigation on the fields this system watered (D15: stored per field), by date: {date =>
  # {Field => entry}} for the days in dates with any, each field as fields_on places it. A field
  # with nothing of its own to water (a rainfed crop, or only plots) shows its irrigated plots'
  # amount (Field.system_irrigation).
  def irrigation_on(dates)
    fields = Field.where(system_id: id).or(Field.where(id: plantings.select(:field_id))).includes(:plantings).order(:name)
      .index_by(&:id)
    Field.system_irrigation(fields.values, dates).sort_by { |(field_id, date), _| [date, fields[field_id].name] }
      .group_by { |(_, date), _| date }
      .filter_map do |date, pairs|
        here = pairs.filter_map { |(field_id, _), entry| [fields[field_id], entry] if fields[field_id].system_id_on(date) == id }
        [date, here.to_h] if here.any?
      end.to_h
  end

  # Every field that is or was on this system, for working out fields_on in the browser
  # (fieldsOn in lib/irrigation.ts): whether it's on it now, and its seasons in the order
  # Field#planting_on picks them, each saying whether it ran here
  def field_seasons
    Field.where(system_id: id).or(Field.where(id: plantings.select(:field_id))).includes(:plantings).order(:name)
      .map do |field|
        seasons = field.plantings.sort_by(&:order_key)
        {id: field.id, name: field.name, here: field.system_id == id,
         seasons: seasons.map { |planting|
           {from: planting.season_start, to: planting.end_date, here: planting.system_id == id, rainfed: planting.rainfed?}
         }}
      end
  end

  private

  # Only the kind's own dimensions are kept, so switching kinds leaves no stale shape behind
  def clear_other_shape
    self.radius_ft = self.arc_start_deg = self.arc_end_deg = nil unless kind == "center"
    self.length_ft = self.travel_ft = self.travel_bearing_deg = nil unless linear?
    self.inches_at_100 = nil unless TIMER_KINDS.include?(kind)
  end

  def move_open_plantings
    plantings.open.update_all(weather_cell_id:)
  end

  def hand_over_plantings
    plantings.where.not(field_id: fields.select(:id))
      .update_all("system_id = (SELECT fields.system_id FROM fields WHERE fields.id = plantings.field_id)")
  end

  def assign_weather_cell
    self.weather_cell = WeatherCell.for(latitude, longitude)
  end

  # A new or moved system gets its cell's forecast and season-to-date weather in the background
  def update_weather
    WeatherUpdateJob.perform_later(weather_cell_id)
  end

  def irrigation_group_on_farm
    errors.add(:irrigation_group, "must be on the same farm") if irrigation_group && irrigation_group.farm_id != farm_id
  end

  def arc_complete
    errors.add(:arc_end_deg, "is needed when a start angle is set") if arc_start_deg && !arc_end_deg
    errors.add(:arc_start_deg, "is needed when an end angle is set") if arc_end_deg && !arc_start_deg
  end
end

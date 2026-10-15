# The daily digest email's contents (PLAN.md Phase 6): every field the user includes that has a
# planting in season today, with its status and outlook, by operation, weather zone (the weather
# grid cell its pivots share, with a summary of its weather), pivot and field. Fields needing
# attention (irrigate, or caution) are also listed first, soonest crossing first.
class DailyDigest
  Entry = Data.define(:field, :status, :outlook) do
    def attention? = ATTENTION.include?(status.status)
    def pivot = field.pivot
    def farm = pivot.farm
    def group = farm.group
  end

  OperationSection = Data.define(:group, :zones)
  # A weather grid cell and the pivots in it; weather: {past:, ahead:} WeatherSummary::Spans.
  # number counts zones within the operation, from 1.
  ZoneSection = Data.define(:cell, :number, :weather, :pivots)
  PivotSection = Data.define(:pivot, :entries)

  ATTENTION = %i[irrigate caution].freeze
  RANK = {irrigate: 0, caution: 1, ok: 2, full: 3}.freeze

  attr_reader :user, :today

  def initialize(user, today: Date.current)
    @user, @today = user, today
  end

  # Most urgent first
  def entries
    @entries ||= begin
      fields = user.digest_fields
        .includes(:soil_type, pivot: {farm: :group}, plantings: [:plant, :canopy_observations]).to_a
      statuses = FieldStatuses.for(fields, today:)
      fields.filter_map do |field|
        status = statuses[field.id]
        Entry.new(field:, status:, outlook: Outlook.for(status, depth: method(:depth))) if status&.phase == :active
      end.sort_by do |entry|
        [RANK.fetch(entry.status.status, RANK.size), entry.status.crossing&.days || PlantingStatus::HORIZON + 1,
          *place_order(entry)]
      end
    end
  end

  def attention = entries.select(&:attention?)

  # The entries by operation, weather zone, pivot and field. Operations, pivots (by farm, then pivot)
  # and fields are in name order; zones in the order of their first pivot.
  def operations
    @operations ||= begin
      weather = WeatherSummary.by_cell(entries.map { |entry| entry.pivot.weather_cell_id }.uniq, today:)
      entries.sort_by { |entry| place_order(entry) }.group_by(&:group).map do |group, group_entries|
        zones = group_entries.group_by { |entry| entry.pivot.weather_cell }.each_with_index.map do |(cell, cell_entries), i|
          pivots = cell_entries.group_by(&:pivot).map { |pivot, pivot_entries| PivotSection.new(pivot:, entries: pivot_entries) }
          ZoneSection.new(cell:, number: i + 1, weather: weather.fetch(cell.id, {}), pivots:)
        end
        OperationSection.new(group:, zones:)
      end
    end
  end

  # Why the digest wouldn't be sent today, or nil if it would be
  def skip_reason
    if !user.digest?
      "The daily email is turned off."
    elsif !user.confirmed?
      "The email address isn't confirmed."
    elsif entries.none?
      "No included field has a crop in season today."
    elsif user.digest_frequency == "needed" && attention.none?
      "No field needs irrigation in the next #{PlantingStatus::LEAD_DAYS} days."
    end
  end

  def deliverable? = skip_reason.nil?

  # Operation names only matter when the fields come from more than one
  def several_groups? = entries.map { |entry| entry.group.id }.uniq.size > 1

  # "WISP: 2 fields to irrigate, 1 to watch (Sun, Oct 4)", or "WISP: 5 fields OK (…)"
  def subject
    irrigate = entries.count { |entry| entry.status.status == :irrigate }
    caution = entries.count { |entry| entry.status.status == :caution }
    summary = if irrigate.positive?
      ["#{fields(irrigate)} to irrigate", ("#{caution} to watch" if caution.positive?)].compact.join(", ")
    elsif caution.positive?
      "#{fields(caution)} to watch"
    else
      "#{fields(entries.size)} OK"
    end
    "WISP: #{summary} (#{Outlook.day(today)})"
  end

  # Inches in the user's units, as the app shows them: "0.75 in", "19.1 mm"
  def depth(inches)
    return "—" if inches.nil?

    value = (metric? ? inches * 25.4 : inches).round(metric? ? 1 : 2)
    format(metric? ? "%.1f mm" : "%.2f in", value.zero? ? 0.0 : value)
  end

  # A range of °F in the user's units: "68–82°F", "20–28°C", or "75°F" when it's one value
  def temperatures(range)
    low, high = [range.begin, range.end].map { |f| (metric? ? (f - 32) * 5 / 9.0 : f).round }
    "#{(low == high) ? low : "#{low}–#{high}"}°#{metric? ? "C" : "F"}"
  end

  private

  def metric? = user.unit_system == "metric"

  def place_order(entry)
    [entry.group.name, entry.group.id, entry.farm.name, entry.farm.id, entry.pivot.name, entry.pivot.id,
      entry.field.name, entry.field.id]
  end

  def fields(count) = (count == 1) ? "1 field" : "#{count} fields"
end

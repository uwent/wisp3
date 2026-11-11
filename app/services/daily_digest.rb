# The daily digest email's contents (PLAN.md Phase 6): the fields the user includes, by operation,
# farm, weather zone (the weather grid cell its pivots share, with a summary of its weather), pivot
# and field. users.digest_scope chooses which included fields are listed: all of them, those with a
# crop in season, those needing irrigation or a reading, or only those needing irrigation. Fields
# needing attention (irrigate, or caution) are also listed first, soonest crossing first. A field
# growing several plantings at once (plots, PLAN.md Phase 8 G.11) has a line for each.
class DailyDigest
  # One line: a planting's PlantingStatus this year, or nil for a field without a planting
  Entry = Data.define(:field, :status, :outlook) do
    def active? = status&.phase == :active
    def attention? = active? && ATTENTION.include?(status.status)
    # Needs irrigation (attention) or has a reading or check due
    def action? = attention? || (active? && status.tasks.any?(&:due))
    def pivot = field.pivot
    def farm = pivot.farm
    def group = farm.group
  end

  OperationSection = Data.define(:group, :farms)
  FarmSection = Data.define(:farm, :zones)
  # A weather grid cell and the farm's pivots in it; weather: {past:, ahead:} WeatherSummary::Spans.
  # number counts zones within the farm, from 1.
  ZoneSection = Data.define(:cell, :number, :weather, :pivots)
  # entries is empty when nothing is listed and the pivot is shown only for its weather
  PivotSection = Data.define(:pivot, :entries)

  ATTENTION = %i[irrigate caution].freeze
  RANK = FieldStatuses::RANK

  attr_reader :user, :today

  def initialize(user, today: Date.current)
    @user, @today = user, today
  end

  # Every included field's plantings (one entry for a field without), most urgent first
  def all_entries
    @all_entries ||= begin
      fields = user.digest_fields
        .includes(:soil_type, pivot: [:weather_cell, {farm: :group}], plantings: [:plant, :canopy_observations, :soil_type]).to_a
      statuses = FieldStatuses.for(fields, today:)
      fields.flat_map do |field|
        (statuses[field.id].presence || [nil]).map do |status|
          outlook = Outlook.for(status, depth: method(:depth)) if status&.phase == :active
          Entry.new(field:, status:, outlook:)
        end
      end.sort_by do |entry|
        [entry.active? ? RANK.fetch(entry.status.status, RANK.size) : RANK.size + 1,
          (entry.status.crossing&.days if entry.active?) || PlantingStatus::HORIZON + 1, *place_order(entry)]
      end
    end
  end

  # The included fields with a crop in season today
  def entries = @entries ||= all_entries.select(&:active?)

  def attention = entries.select(&:attention?)

  # The included fields the email lists, by the user's digest_scope
  def listed
    @listed ||= case user.digest_scope
    when "all" then all_entries
    when "needs_action" then entries.select(&:action?)
    when "needs_irrigation" then attention
    else entries
    end
  end

  # Why the list is empty, when it is: "No field needs irrigation or a reading today."
  def nothing_listed
    return if listed.any?

    case user.digest_scope
    when "needs_action" then "No field needs irrigation or a reading today."
    when "needs_irrigation" then "No field needs irrigation now or within #{PlantingStatus::LEAD_DAYS} days."
    else "No included field has a crop in season today."
    end
  end

  # The listed fields by operation, farm, weather zone and pivot, in name order (zones in the order
  # of their first pivot). With nothing listed, the in-season fields' pivots (or, with none in
  # season, every included pivot), for their weather only.
  def operations
    @operations ||= begin
      shown = listed.presence || entries.presence || all_entries
      weather = WeatherSummary.by_cell(shown.map { |entry| entry.pivot.weather_cell_id }.uniq, today:)
      shown.sort_by { |entry| place_order(entry) }.group_by(&:group).map do |group, group_entries|
        OperationSection.new(group:, farms: group_entries.group_by(&:farm).map do |farm, farm_entries|
          zones = farm_entries.group_by { |entry| entry.pivot.weather_cell }.each_with_index.map do |(cell, cell_entries), i|
            pivots = cell_entries.group_by(&:pivot).map do |pivot, pivot_entries|
              PivotSection.new(pivot:, entries: listed.any? ? pivot_entries : [])
            end
            ZoneSection.new(cell:, number: i + 1, weather: weather.fetch(cell.id, {}), pivots:)
          end
          FarmSection.new(farm:, zones:)
        end)
      end
    end
  end

  # Operation and farm headings matter only when the included fields span more than one
  def several_groups? = all_entries.map { |entry| entry.group.id }.uniq.size > 1
  def several_farms? = all_entries.map { |entry| entry.farm.id }.uniq.size > 1

  # The one operation and farm the email covers, for a line at the top when their headings are left
  # out: [[“Operation”, name], [“Farm”, name]]
  def context
    first = all_entries.first or return []
    [(["Operation", first.group.name] unless several_groups?), (["Farm", first.farm.name] unless several_farms?)].compact
  end

  # How much the email lists of what it covers
  Counts = Data.define(:fields, :pivots, :covered_fields, :covered_pivots, :planted)

  def counts
    Counts.new(fields: listed.map(&:field).uniq.size, pivots: listed.map(&:pivot).uniq.size,
      covered_fields: all_entries.map(&:field).uniq.size, covered_pivots: all_entries.map(&:pivot).uniq.size,
      planted: all_entries.select(&:status).map(&:field).uniq.size)
  end

  # Why the digest wouldn't be sent today, or nil if it would be
  def skip_reason
    if !user.digest?
      "The daily email is turned off."
    elsif !user.confirmed?
      "The email address isn't confirmed."
    elsif all_entries.none?
      "No fields are included in your daily email."
    elsif user.digest_frequency == "daily_all_year"
      nil
    elsif entries.none?
      "No included field has a crop in season today."
    elsif user.digest_frequency == "needed" && attention.none?
      "No field needs irrigation in the next #{PlantingStatus::LEAD_DAYS} days."
    end
  end

  def deliverable? = skip_reason.nil?

  # "WISP: 2 fields to irrigate, 1 to watch (Sun, Oct 4)", "WISP: 5 fields OK (…)", or "WISP: no
  # crops in season (…)"
  def subject
    # Fields, not plantings: a field of plots counts once, at its most urgent
    worst = entries.group_by(&:field).transform_values { |list| FieldStatuses.most_urgent(list.map(&:status)).status }
    irrigate = worst.count { |_, status| status == :irrigate }
    caution = worst.count { |_, status| status == :caution }
    summary = if irrigate.positive?
      ["#{fields(irrigate)} to irrigate", ("#{caution} to watch" if caution.positive?)].compact.join(", ")
    elsif caution.positive?
      "#{fields(caution)} to watch"
    elsif entries.any?
      "#{fields(worst.size)} OK"
    else
      "no crops in season"
    end
    "WISP: #{summary} (#{Outlook.day(today)})"
  end

  # Inches in the user's units, as the app shows them: "0.75 in", "19.1 mm"
  def depth(inches)
    return "—" if inches.nil?

    value = (metric? ? inches * 25.4 : inches).round(metric? ? 1 : 2)
    format(metric? ? "%.1f mm" : "%.2f in", value.zero? ? 0.0 : value)
  end

  # Part of a field's size: "100 × 20 ft (0.05 ac)", "30 × 6 m (0.02 ha)", or "0.25 ac"
  def plot(planting)
    area = metric? ? format("%.2f ha", planting.area_acres * 0.404686) : format("%.2f ac", planting.area_acres)
    return area unless planting.plot_length_ft
    length, width = [planting.plot_length_ft, planting.plot_width_ft].map { |ft| (metric? ? ft * 0.3048 : ft).round }
    "#{length} × #{width} #{metric? ? "m" : "ft"} (#{area})"
  end

  # A range of °F in the user's units: "68–82°F", "20–28°C", or "75°F" when it's one value
  def temperatures(range)
    low, high = [range.begin, range.end].map { |f| (metric? ? (f - 32) * 5 / 9.0 : f).round }
    "#{(low == high) ? low : "#{low}–#{high}"}°#{metric? ? "C" : "F"}"
  end

  private

  def metric? = user.unit_system == "metric"

  def place_order(entry)
    [entry.group.name.downcase, entry.group.id, entry.farm.name.downcase, entry.farm.id, entry.pivot.name.downcase,
      entry.pivot.id, entry.field.name.downcase, entry.field.id, entry.status&.planting&.partial? ? 1 : 0,
      entry.status&.planting&.season_start || today, entry.status&.planting&.id || 0]
  end

  def fields(count) = (count == 1) ? "1 field" : "#{count} fields"
end

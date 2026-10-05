# The daily digest email's contents (PLAN.md Phase 6): every field the user includes that has a
# planting in season today, with its status and outlook. Fields needing attention (irrigate, or
# caution) come first, soonest crossing first.
class DailyDigest
  Entry = Data.define(:field, :status, :outlook) do
    def attention? = ATTENTION.include?(status.status)
    def farm = field.pivot.farm
    def group = farm.group
  end

  ATTENTION = %i[irrigate caution].freeze
  RANK = {irrigate: 0, caution: 1, ok: 2, full: 3}.freeze

  attr_reader :user, :today

  def initialize(user, today: Date.current)
    @user, @today = user, today
  end

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
          entry.group.name, entry.farm.name, entry.field.pivot.name, entry.field.name]
      end
    end
  end

  def attention = entries.select(&:attention?)
  def others = entries.reject(&:attention?)

  # Why nothing would be sent today, or nil if it would be
  def skip_reason
    if !user.digest? then "The digest is turned off."
    elsif !user.confirmed? then "The email address isn't confirmed."
    elsif entries.none? then "No included field has a crop in season today."
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

    metric = user.unit_system == "metric"
    value = (metric ? inches * 25.4 : inches).round(metric ? 1 : 2)
    format(metric ? "%.1f mm" : "%.2f in", value.zero? ? 0.0 : value)
  end

  private

  def fields(count) = (count == 1) ? "1 field" : "#{count} fields"
end

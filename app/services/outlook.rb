# What a field's projection means, in words, for the daily digest. The same wording as the field
# page and dashboard cards (app/frontend/lib/outlook.ts); change both together.
class Outlook
  # dry: for a field using only entered rain, when it needs water if no rain falls, where that's
  # sooner than the forecast case (Q7); otherwise nil
  Result = Data.define(:urgent, :headline, :detail, :chance, :dry)

  # status: a PlantingStatus; depth: formats inches in the reader's units. Nil outside the season.
  def self.for(status, depth:)
    return unless status.phase == :active && status.current

    new(status, depth).result
  end

  def initialize(status, depth)
    @status, @depth = status, depth
  end

  def result
    crossing = @status.crossing
    if crossing&.days&.zero?
      Result.new(urgent: true, headline: target? ? "Below target now" : "At the irrigation point now",
        detail: "About #{@depth.call(crossing.refill)} refills the root zone to field capacity.", chance: nil, dry: nil)
    elsif crossing
      scenarios = chance_by(crossing.date)
      Result.new(urgent: crossing.days <= PlantingStatus::LEAD_DAYS, headline: "Irrigate by #{Outlook.day(crossing.date)}",
        detail: "Projected to reach #{level} #{relative_day(crossing.date)}; about #{@depth.call(crossing.refill)} " \
          "would refill it to field capacity then.",
        chance: scenarios && "#{scenarios} reach it by then.", dry:)
    elsif (last = @status.forecast_days.last)
      scenarios = chance_by(last.inputs.date)
      Result.new(urgent: false, headline: "No irrigation needed through #{Outlook.day(last.inputs.date)}",
        detail: "Projected to stay above #{level} through the forecast.",
        chance: (scenarios && !scenarios.start_with?("0 ")) ? "#{scenarios} reach it by then." : nil, dry:)
    end
  end

  # "Wed, Oct 7"
  def self.day(date) = date.strftime("%a, %b %-d")

  private

  def target? = !@status.params.target_in.nil?

  def dry
    dry_crossing, crossing = @status.dry_crossing, @status.crossing
    sooner = dry_crossing && (crossing.nil? || dry_crossing.date < crossing.date)
    return unless sooner

    "If no rain falls: irrigate by #{Outlook.day(dry_crossing.date)} (#{relative_day(dry_crossing.date)})."
  end

  def level = target? ? "its target" : "the irrigation point"

  def chance_by(date)
    members = @status.ensemble_size
    chance = @status.ensemble.find { |band| band.date == date }&.chance
    "#{(chance * members).round} of #{members} forecast scenarios" if chance && members.positive?
  end

  def relative_day(date)
    case (days = (date - @status.today).to_i)
    when 0 then "today"
    when 1 then "tomorrow"
    when -1 then "yesterday"
    else (days > 0) ? "in #{days} days" : "#{-days} days ago"
    end
  end
end

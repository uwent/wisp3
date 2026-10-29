# A planting's to-do list while its season is on (PLAN.md Phase 6.7), for the field page, the
# dashboard cards and the daily email: the readings that keep the model on track, as the legacy
# user guide advised (soil moisture about weekly; percent cover about weekly from emergence until
# the canopy covers about 80%), and canopy readings to check when they disagree with the crop's
# curve (Canopy#check). lib/guidance.ts explains the same advice in its paragraphs.
class PlantingTasks
  # How often a reading should be entered, in days
  READING_EVERY = 7
  # Percent cover readings can stop once the canopy covers this much of the ground
  FULL_COVER_PCT = 80

  # kind: :soil_moisture, :canopy or :canopy_check. last_date: the latest reading, if any. due:
  # whether it's to do now. note: "due", "canopy closed", "vines killed" or nil. todo: what to do, in
  # a line (when due). message: more about it, for the canopy check.
  Task = Data.define(:kind, :label, :last_date, :due, :note, :todo, :message)

  def initialize(status)
    @status = status
    @planting, @today = status.planting, status.today
  end

  def all
    return [] unless @status.phase == :active

    [soil_moisture, canopy, canopy_check].compact
  end

  def due = all.select(&:due)

  private

  def soil_moisture
    last = @status.days.rfind { |day| day.inputs.moisture_source }&.inputs&.date
    reading(:soil_moisture, "Soil moisture", last, "Enter a soil moisture reading")
  end

  def canopy
    return if @today < @planting.emergence_date

    lai = @planting.et_method == "lai"
    attribute = lai ? :lai : :pct_cover
    last = @planting.canopy_observations.select { |obs| obs.date <= @today && obs[attribute] }.max_by(&:date)
    # On LAI the curve stands in for readings until the grower starts entering them
    return if lai && !last

    label = lai ? "Leaf area index (LAI)" : "Percent cover"
    # From vine kill the canopy ramps down on its own; soil moisture readings carry on to harvest
    if @planting.vine_kill_date && @today >= @planting.vine_kill_date
      return Task.new(kind: :canopy, label:, last_date: last&.date, due: false, note: "vines killed", todo: nil,
        message: nil)
    end
    if !lai && last && last.pct_cover >= FULL_COVER_PCT
      return Task.new(kind: :canopy, label:, last_date: last.date, due: false, note: "canopy closed", todo: nil,
        message: nil)
    end
    reading(:canopy, label, last&.date, lai ? "Enter an LAI reading" : "Enter a percent cover reading")
  end

  def reading(kind, label, last, todo)
    due = last.nil? || (@today - last).to_i > READING_EVERY
    since = last ? "last #{day(last)}" : "none yet this season"
    Task.new(kind:, label:, last_date: last, due:, note: ("due" if due), todo: ("#{todo} (#{since})" if due),
      message: nil)
  end

  def canopy_check
    check = @status.canopy.check or return
    crop = @planting.plant.name.downcase
    keep = if @planting.effective_canopy_interpolation == "curve"
      " WISP still follows the typical curve through your readings; you can choose straight lines between " \
        "readings in Setup instead."
    end

    if check.days_ahead
      days, way = check.days_ahead.abs, check.days_ahead.positive? ? "ahead of" : "behind"
      todo = "Check your canopy readings: they're about #{days} days #{way} the typical #{crop} curve"
      message = "Your canopy readings run about #{days} days #{way} the typical #{crop} curve. If your crop isn't " \
        "growing that much #{check.days_ahead.positive? ? "faster" : "slower"}, check the emergence date " \
        "(#{day(@planting.emergence_date)}) and your readings.#{keep}"
    else
      drop = check.drop
      todo = "Check your #{day(drop[:date])} canopy reading, which is lower than the one before"
      message = "Your canopy reading on #{day(drop[:date])} (#{pct(drop[:to])}) is lower than the one before it " \
        "(#{pct(drop[:from])}), while the #{crop} curve is still growing or holding. If the canopy didn't really " \
        "shrink, check the reading.#{keep}"
    end
    Task.new(kind: :canopy_check, label: "Canopy readings", last_date: nil, due: true, note: nil, todo:, message:)
  end

  def day(date) = date.strftime("%b %-d")

  def pct(value) = "#{(value % 1).zero? ? value.to_i : value.round(1)}%"
end

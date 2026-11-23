# A planting's to-do list while its season is on, for the field page, the
# dashboard cards and the daily email: the readings that keep the model on track, as the legacy
# user guide advised (soil moisture about weekly; percent cover about weekly from emergence until
# the canopy covers about 80%), and canopy readings to check when they disagree with the crop's
# curve (Canopy#check). lib/guidance.ts explains the same advice in its paragraphs. And the
# irrigation check: a balance that has read "Irrigate now" for days with no irrigation entered asks
# whether the grower irrigated and didn't enter it, before they decide the model is wrong.
class PlantingTasks
  # How often a reading should be entered, in days
  READING_EVERY = 7
  # Percent cover readings can stop once the canopy covers this much of the ground
  FULL_COVER_PCT = 80

  # The irrigation check asks after this many days in a row at or below the threshold, ending today
  IRRIGATION_CHECK_DAYS = 2

  # kind: :irrigation_check, :soil_moisture, :canopy or :canopy_check. last_date: the latest reading,
  # if any. due: whether it's to do now. note: "due", "canopy closed", "vines killed", "optional" or
  # nil. todo: what to do, in a line (when due). message: more about it, for the checks. date: the
  # day daily entry opens on to do it (the irrigation check's first day), or nil.
  Task = Data.define(:kind, :label, :last_date, :due, :note, :todo, :message, :date) do
    def initialize(date: nil, **) = super
  end

  def initialize(status)
    @status = status
    @planting, @today = status.planting, status.today
  end

  # In season, every reading with whether it's due, and the canopy check; once the season has ended,
  # the readings with their last dates only (the planting page lists them), none of them due. A
  # rainfed crop's readings are optional: its balance follows the weather, and they only correct it.
  def all
    case @status.phase
    when :active
      return [soil_moisture, canopy].compact.map { |task| optional(task) } + [canopy_check].compact if @status.rainfed?
      [irrigation_check, soil_moisture, canopy, canopy_check].compact
    when :ended
      [soil_moisture, canopy].compact.map { |task| task.with(due: false, note: (task.note unless task.due), todo: nil) }
    else []
    end
  end

  def due = all.select(&:due)

  # The percent cover (or LAI) reading's task for planting on date: nil before emergence, and on LAI
  # until the grower starts entering readings (the curve stands in until then). A cutting restarts
  # the canopy, so only readings since the latest one count (one on its date belongs to the
  # regrowth, as in CutCanopy). Needs only the planting's readings and cuttings, not its balance
  # (daily entry asks it for any date).
  def self.canopy(planting, date)
    return if date < planting.emergence_date

    lai = planting.et_method == "lai"
    attribute = lai ? :lai : :pct_cover
    cut = planting.cutting_dates.select { |day| day > planting.emergence_date && day <= date }.max
    last = planting.canopy_observations
      .select { |obs| obs.date <= date && (cut.nil? || obs.date >= cut) && obs[attribute] }.max_by(&:date)
    return if lai && !last

    label = lai ? "Leaf area index (LAI)" : "Percent cover"
    # From vine kill the canopy ramps down on its own; soil moisture readings carry on to harvest
    if planting.vine_kill_date && date >= planting.vine_kill_date
      return Task.new(kind: :canopy, label:, last_date: last&.date, due: false, note: "vines killed", todo: nil,
        message: nil)
    end
    if !lai && last && last.pct_cover >= FULL_COVER_PCT
      return Task.new(kind: :canopy, label:, last_date: last.date, due: false, note: "canopy closed", todo: nil,
        message: nil)
    end
    reading(:canopy, label, last&.date, lai ? "Enter an LAI reading" : "Enter a percent cover reading", date,
      none: cut && "none since the #{cut.strftime("%b %-d")} cutting")
  end

  def self.reading(kind, label, last, todo, today, none: nil)
    due = last.nil? || (today - last).to_i > READING_EVERY
    since = last ? "last #{last.strftime("%b %-d")}" : none || "none yet this season"
    Task.new(kind:, label:, last_date: last, due:, note: ("due" if due), todo: ("#{todo} (#{since})" if due),
      message: nil)
  end

  private

  def soil_moisture
    last = @status.days.rfind { |day| day.inputs.moisture_source }&.inputs&.date
    reading(:soil_moisture, "Soil moisture", last, "Enter a soil moisture reading")
  end

  # On LAI the curve stands in until the first reading, so the reading is listed as optional
  def canopy
    task = self.class.canopy(@planting, @today)
    return task if task || @planting.et_method != "lai" || @today < @planting.emergence_date

    Task.new(kind: :canopy, label: "Leaf area index (LAI)", last_date: nil, due: false, note: "optional", todo: nil,
      message: nil)
  end

  def reading(kind, label, last, todo) = self.class.reading(kind, label, last, todo, @today)

  # A rainfed crop's reading isn't due, but for the canopy reading a crop with no curve needs to have any ET
  def optional(task)
    return task if !task.due || (task.kind == :canopy && @status.needs_canopy?)
    task.with(due: false, note: "optional", todo: nil)
  end

  # Due when the balance has been at or below the threshold (status irrigate, or below the target)
  # for IRRIGATION_CHECK_DAYS or more days in a row ending today, with no irrigation entered (an
  # entered 0 counts: the grower says there was none) for the field, its plot or by its system on
  # any of them. Not on read-only pages (time travel, the example farm), which can't enter it.
  def irrigation_check
    return if @status.as_of || Current.as_of || @status.status.in?([nil, :needs_canopy]) || @status.weather_pending?

    threshold = @status.threshold
    run = @status.days.reverse.take_while do |day|
      day.inputs.et0 && day.result.ad <= threshold && day.inputs.irrigation_source == :none
    end
    return if run.size < IRRIGATION_CHECK_DAYS || run.first.inputs.date != @today

    since = run.last.inputs.date
    level = @status.params.target_in ? "your target" : "the irrigation point"
    Task.new(kind: :irrigation_check, label: "Irrigation", last_date: nil, due: true, note: nil,
      todo: "Irrigated since #{Outlook.day(since)}? Enter it so the balance catches up.",
      message: "The balance has been at or below #{level} since #{Outlook.day(since)} with no irrigation " \
        "entered. If you irrigated, enter it in daily entry and the balance will catch up.", date: since)
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

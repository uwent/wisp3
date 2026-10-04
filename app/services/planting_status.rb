# A planting's season as the UI shows it: the balance for each day from season start through today
# (or the season's end), today's status, the latest rain and irrigation, and season totals, with
# entered rain set against the modeled rain for the same days (Q7).
class PlantingStatus
  Totals = Data.define(:rain, :irrigation, :adj_et, :deep_drainage, :rain_model, :entered_rain_days,
    :entered_rain, :entered_rain_model)

  attr_reader :planting, :today

  # weather: and records: are passed to PlantingBalance (pages showing many plantings preload them)
  def initialize(planting, today: Date.current, weather: nil, records: nil)
    @planting, @today = planting, today
    @balance = PlantingBalance.new(planting, weather:, records:)
  end

  def params = @balance.params

  # :upcoming (before season start), :active, or :ended
  def phase
    if today < planting.season_start then :upcoming
    elsif today > planting.end_date then :ended
    else :active
    end
  end

  def days = @days ||= (phase == :upcoming) ? [] : @balance.days(through: [today, planting.end_date].min)

  # Today's day, or the season's last
  def current = days.last

  def status = current && WaterBalance.status(params, current.result.ad)

  # The season has started but no weather has arrived for it yet (a new pivot, before its backfill)
  def weather_pending? = days.any? && days.none? { |day| day.inputs.et0 }

  def last_rain = days.rfind { |day| day.inputs.rain.to_f.positive? }
  def last_irrigation = days.rfind { |day| day.inputs.irrigation.to_f.positive? }

  def totals
    entered = days.select { |day| %i[entered group].include?(day.inputs.rain_source) && day.inputs.rain_model }
    Totals.new(
      rain: sum(days) { |day| day.inputs.rain }, irrigation: sum(days) { |day| day.inputs.irrigation },
      adj_et: sum(days) { |day| day.result.adj_et }, deep_drainage: sum(days) { |day| day.result.deep_drainage },
      rain_model: sum(days) { |day| day.inputs.rain_model }, entered_rain_days: entered.size,
      entered_rain: sum(entered) { |day| day.inputs.rain }, entered_rain_model: sum(entered) { |day| day.inputs.rain_model }
    )
  end

  private

  def sum(days, &) = days.sum { |day| yield(day).to_f }.round(WaterBalance::PRECISION)
end

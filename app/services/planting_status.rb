# A planting's season as the UI shows it: the balance for each day from season start through today
# (or the season's end), today's status, the latest rain and irrigation, and season totals, with
# entered rain set against the modeled rain for the same days (Q7). While the season is on, also
# the projection (PLAN.md §6): the same balance through the forecast, with planned irrigation (entries
# on future dates), the ensemble's range around it, and when the field reaches its threshold. A field
# that uses only entered rain also gets a projection with no rain at all (Q7), beside the forecast's.
class PlantingStatus
  Totals = Data.define(:rain, :irrigation, :adj_et, :deep_drainage, :rain_model, :entered_rain_days,
    :entered_rain, :entered_rain_model)
  # The first day (today or ahead) the projection is at or below the threshold, and the depth that
  # refills the root zone to field capacity then
  Crossing = Data.define(:date, :days, :ad, :refill)

  # Days projected after today: the forecast's 16 days include today
  HORIZON = Weather::Fetcher::FORECAST_DAYS - 1
  # A field OK today but projected to reach its threshold within this many days is "caution" (§5.5)
  LEAD_DAYS = 3

  attr_reader :planting, :today

  # weather: and records: are passed to PlantingBalance (pages showing many plantings preload them).
  # ensemble: the cell's ensemble members (WeatherForecast#members); loaded if not given.
  def initialize(planting, today: Date.current, weather: nil, records: nil, ensemble: :load)
    @planting, @today, @ensemble_members = planting, today, ensemble
    @balance = PlantingBalance.new(planting, weather:, records:, today:)
  end

  def params = @balance.params

  # :upcoming (before season start), :active, or :ended
  def phase
    if today < planting.season_start then :upcoming
    elsif today > planting.end_date then :ended
    else :active
    end
  end

  # The season through today, or its end
  def days = @days ||= balance_days.select { |day| day.inputs.date <= today }

  # The projection: the days after today that have forecast weather, through the season's end
  def forecast_days
    @forecast_days ||= balance_days.select { |day| day.inputs.date > today }.take_while { |day| day.inputs.et0 }
  end

  # Today's day, or the season's last
  def current = days.last

  # Today's status; caution when it's fine today but the projection reaches the threshold soon
  def status
    return unless current
    today_status = WaterBalance.status(params, current.result.ad)
    soon = phase == :active && crossing && crossing.days <= LEAD_DAYS
    (%i[full ok].include?(today_status) && soon) ? :caution : today_status
  end

  # The AD to stay above: the target, or the irrigation point (AD 0) without one
  def threshold = params.target_in || 0.0

  def crossing
    return @crossing if defined?(@crossing)
    @crossing = first_crossing(([current] + forecast_days).compact.map(&:result))
  end

  # Whether days without entered rain take the model's (the field's setting, or its group's)
  def use_model_precip? = planting.field.effective_use_model_precip

  # For a field using only entered rain: the projection's balance (WaterBalance::Results) with no
  # forecast rain, keeping planned irrigation and any rain entered ahead. Empty otherwise.
  def dry_projection
    @dry_projection ||= if !use_model_precip? && phase == :active && current && forecast_days.any?
      dry_days = forecast_days.map do |day|
        rain = %i[forecast model].include?(day.inputs.rain_source) ? 0.0 : day.inputs.rain
        WaterBalance::Day.new(date: day.inputs.date, et0: day.inputs.et0, rain:, irrigation: day.inputs.irrigation,
          soil_moisture_pct: day.inputs.soil_moisture_pct, canopy: day.canopy)
      end
      WaterBalance.run(params, dry_days, initial_ad: current.result.ad, et_history:)
    else
      []
    end
  end

  # When the no-rain projection reaches the threshold (nil without one)
  def dry_crossing
    return @dry_crossing if defined?(@dry_crossing)
    @dry_crossing = dry_projection.any? ? first_crossing([current.result] + dry_projection) : nil
  end

  # EnsembleProjection::Bands for forecast_days (empty without an ensemble)
  def ensemble
    @ensemble ||= if phase == :active && current && forecast_days.any? && ensemble_members.present?
      EnsembleProjection.run(params, days: forecast_days, members: ensemble_members, start_ad: current.result.ad,
        threshold:, et_history:, already_crossed: current.result.ad <= threshold)
    else
      []
    end
  end

  def ensemble_size = ensemble.any? ? ensemble_members.size : 0

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

  # The first of results (today's, then the projection's) at or below the threshold, while the season is on
  def first_crossing(results)
    result = results.find { |r| r.ad <= threshold } if phase == :active
    result && Crossing.new(date: result.date, days: (result.date - today).to_i, ad: result.ad,
      refill: (params.ad_max - result.ad).round(WaterBalance::PRECISION))
  end

  # The past week's computed crop ET, so a run starting today gap-fills as the season's would
  def et_history
    days.filter_map { |day| [day.inputs.date, day.result.adj_et] if day.result.et_source == :computed }
      .last(WaterBalance::GAP_FILL_DAYS)
  end

  # Season start through today plus the projection's days (within the season); none before it starts
  def balance_days
    return @balance_days ||= [] if phase == :upcoming
    @balance_days ||= @balance.days(through: [(phase == :active) ? today + HORIZON : today, planting.end_date].min)
  end

  def ensemble_members
    @ensemble_members = planting.field.pivot.weather_cell&.latest_ensemble&.members if @ensemble_members == :load
    @ensemble_members
  end

  def sum(days, &) = days.sum { |day| yield(day).to_f }.round(WaterBalance::PRECISION)
end

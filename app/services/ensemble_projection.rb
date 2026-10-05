# The range of outcomes ahead (PLAN.md §6): the water balance run once per ensemble member from
# today's AD, through the deterministic projection's days. Each member brings its own et0 and, where
# the day's rain is modeled, its own rain; entered values (planned irrigation) are kept. Plain Ruby.
module EnsembleProjection
  # chance: the share of members at or below the threshold on this day or any day before it
  Band = Data.define(:date, :p10, :p50, :p90, :chance)

  module_function

  # days: the projection's PlantingBalance::Days (resolved inputs and canopy) after today.
  # members: [{date => {et0:, precip:}}, ...]. start_ad: today's AD, or nil if today is already at or
  # below threshold (every member then counts as crossed). et_history: [[date, adj_et], ...] before
  # the first day, for gap fill.
  def run(params, days:, members:, start_ad:, threshold:, et_history: [], already_crossed: false)
    return [] if days.empty? || members.empty?

    runs = members.map do |member|
      balance_days = days.map do |day|
        weather = member[day.inputs.date] || {}
        rain = (day.inputs.rain_source == :forecast) ? (weather[:precip] || day.inputs.rain) : day.inputs.rain
        WaterBalance::Day.new(date: day.inputs.date, et0: weather[:et0], rain:, irrigation: day.inputs.irrigation,
          soil_moisture_pct: day.inputs.soil_moisture_pct, canopy: day.canopy)
      end
      WaterBalance.run(params, balance_days, initial_ad: start_ad, et_history:).map(&:ad)
    end

    crossed = Array.new(runs.size, already_crossed)
    days.each_with_index.map do |day, i|
      ads = runs.map { |ad| ad[i] }
      ads.each_with_index { |ad, member| crossed[member] ||= ad <= threshold }
      Band.new(date: day.inputs.date, p10: percentile(ads, 0.1), p50: percentile(ads, 0.5), p90: percentile(ads, 0.9),
        chance: (crossed.count(true).to_f / runs.size).round(2))
    end
  end

  # Linear interpolation between the closest ranks
  def percentile(values, fraction)
    sorted = values.sort
    rank = fraction * (sorted.size - 1)
    low, high = sorted[rank.floor], sorted[rank.ceil]
    (low + (high - low) * (rank - rank.floor)).round(WaterBalance::PRECISION)
  end
end

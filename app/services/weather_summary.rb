# A cell's weather in brief, for the daily digest: rain and ET totals and the range of highs and
# lows over the last week of stored days and the next week of the latest forecast (today onward).
# A value missing from every day is nil, never 0.
class WeatherSummary
  DAYS = 7

  # days: how many days had weather; tmax and tmin are Ranges
  Span = Data.define(:days, :precip, :et0, :tmax, :tmin)

  # {cell_id => {past: Span, ahead: Span}} for several cells in two queries; either is nil
  # without weather for those days
  # observed: the stored days after today in place of the forecast (the example farm)
  def self.by_cell(cell_ids, today:, observed: Current.as_of.present?)
    columns = %i[precip_in et0_in tmax_f tmin_f]
    stored = ->(dates) {
      WeatherDay.where(weather_cell_id: cell_ids, date: dates)
        .pluck(:weather_cell_id, *columns).group_by(&:first).transform_values { |rows| rows.map { |row| row.drop(1) } }
    }
    past = stored.call((today - DAYS)...today)
    following = observed ? stored.call(today...(today + DAYS)) : {}
    forecasts = observed ? {} : WeatherForecast.deterministic.latest_by_cell(cell_ids)

    cell_ids.to_h do |cell_id|
      ahead = if observed
        following[cell_id]
      else
        (forecasts[cell_id]&.days || {}).select { |date, _| date >= today && date < today + DAYS }
          .values.map { |values| values.values_at(*columns.map(&:to_s)) }
      end
      [cell_id, {past: span(past[cell_id]), ahead: span(ahead)}]
    end
  end

  # rows: [precip, et0, tmax, tmin] for each day
  def self.span(rows)
    return if rows.blank?

    precip, et0, tmax, tmin = rows.transpose.map(&:compact)
    Span.new(days: rows.size, precip: total(precip), et0: total(et0), tmax: range(tmax), tmin: range(tmin))
  end

  def self.total(values) = values.any? ? values.sum : nil

  def self.range(values) = values.any? ? values.min..values.max : nil

  private_class_method :span, :total, :range
end

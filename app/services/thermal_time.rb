# Degree days between dates at a weather cell, for a crop's base and upper temperatures
# (Weather::DegreeDays.aquacrop), from CellTemperatures: the clock a canopy curve in thermal time
# runs on (CanopyCurve#from, C23). Sums are kept as running totals from the first date
# asked, so each lookup is constant time once the days around it have been added up.
class ThermalTime
  def initialize(temperatures, base_c:, upper_c:)
    @temperatures, @base_c, @upper_c = temperatures, base_c, upper_c
    @origin = nil
  end

  # The dates a planting's curve can look at: from its emergence less the most a fit shifts it
  # (CanopyFit::MAX_SHIFT) through its end date plus the most the curve check looks ahead
  # (Canopy::MAX_SHIFT). Pages load the temperatures for at least these (CellTemperatures).
  def self.dates_for(planting) = (planting.emergence_date - CanopyFit::MAX_SHIFT)..(planting.end_date + Canopy::MAX_SHIFT)

  # Degree days on date (°C days)
  def on(date)
    tmax, tmin = @temperatures.on(date)
    Weather::DegreeDays.aquacrop(tmax, tmin, base_c: @base_c, upper_c: @upper_c) || 0.0
  end

  # Degree days over the days from `from` up to, not including, `to` (negative if `to` is earlier)
  def between(from, to) = total(to) - total(from)

  # Identifies the temperatures from `from` through `to`, for caching what's fitted to them
  # (CanopyFit.fetch): it changes when a stored day is revised or a forecast replaced
  def digest(from, to)
    Digest::SHA256.hexdigest((from..to).map { |date| @temperatures.on(date) }.inspect).first(12)
  end

  private

  # Degree days from the origin (the first date asked) up to date
  def total(date)
    unless @origin
      @origin = date
      @forward, @backward = [0.0], [0.0]
    end
    i = (date - @origin).to_i
    if i >= 0
      @forward << @forward.last + on(@origin + @forward.size - 1) while @forward.size <= i
      @forward[i]
    else
      @backward << @backward.last - on(@origin - @backward.size) while @backward.size <= -i
      @backward[-i]
    end
  end
end

# A planting's canopy (percent cover, or LAI) on each day (PLAN.md §5.3).
#
# Readings are anchor points with linear interpolation between them. Before emergence the
# canopy is 0; from emergence it rises linearly from 0 to the first reading; after the last
# reading it is held until end_date (legacy held it for only 6 days, C3); after end_date it is 0.
# Readings dated before emergence are ignored (for perennials, use the green-up date as
# emergence).
#
# With no readings, an LAI planting follows its plant's growth curve (CanopyModel), or stays at 0
# if the plant has none.
class Canopy
  def initialize(emergence_date:, end_date:, observations: [], curve: nil)
    @emergence_date, @end_date, @curve = emergence_date, end_date, curve
    @anchors = observations.select { |date, _| date >= emergence_date }.sort_by(&:first)
    @anchors.unshift([emergence_date, 0.0]) if @anchors.any? && @anchors.first.first > emergence_date
  end

  # For a Planting, from its canopy observations (percent cover or LAI, by its ET method)
  def self.for(planting)
    attribute = (planting.et_method == "lai") ? :lai : :pct_cover
    observations = planting.canopy_observations.filter_map { |obs| [obs.date, obs[attribute]] if obs[attribute] }
    curve = planting.plant.canopy_model if attribute == :lai
    new(emergence_date: planting.emergence_date, end_date: planting.end_date, observations:, curve:)
  end

  def on(date)
    return 0.0 if date < @emergence_date || date > @end_date
    return curve_value(date) if @anchors.empty?

    after = @anchors.index { |anchor_date, _| anchor_date >= date }
    return @anchors.last.last unless after # held after the last reading
    return @anchors[after].last if @anchors[after].first == date

    (date0, value0), (date1, value1) = @anchors[after - 1], @anchors[after]
    value0 + (value1 - value0) * (date - date0) / (date1 - date0)
  end

  private

  def curve_value(date)
    CanopyModel.lai(@curve, (date - @emergence_date).to_i) || 0.0
  end
end

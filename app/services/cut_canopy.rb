# A perennial planting's canopy with cuttings: the season splits at each
# cutting, and every piece follows the regrowth curve from its start (the first from emergence, i.e.
# green-up), fitted to the readings within it only. So the canopy drops to stubble at a cutting and
# regrows, a sawtooth, instead of one curve smoothed across the cuts. A reading on a cutting's date
# belongs to the regrowth. Answers what Canopy does for PlantingBalance, the grid and the tasks.
class CutCanopy
  # pieces: [Canopy, …] in date order, each from its start (emergence_date) to the day before the next
  def initialize(pieces)
    @pieces = pieces
  end

  # For a Planting on the perennial curve with cuttings; through: and temperatures: as Canopy.for
  def self.for(planting, cuttings, through: nil, temperatures: nil)
    curve = planting.cover_curve
    clock = Canopy.thermal_clock(curve, planting, temperatures)
    observations = planting.canopy_observations.filter_map do |obs|
      [obs.date, obs.pct_cover] if obs.pct_cover && (through.nil? || obs.date <= through)
    end
    starts = [planting.emergence_date, *cuttings.select { |date| date > planting.emergence_date }.sort.uniq]
    pieces = starts.each_with_index.map do |start, i|
      finish = starts[i + 1] ? starts[i + 1] - 1 : planting.end_date
      fit_curve = ->(**fit) { curve.from(start, clock:, **fit) }
      readings = observations.select { |date, _| date.between?(start, finish) }
      Canopy.new(emergence_date: start, end_date: finish, observations: readings, curve: fit_curve.call,
        fit_curve:, fit_key: ["cover", curve.key, curve.digest, start, *Canopy.thermal_key(clock, start, readings)],
        follow_curve: planting.canopy_interpolation != "linear", thermal: clock.present?)
    end
    new(pieces)
  end

  def on(date) = piece(date)&.on(date) || 0.0

  # The regrowth curve each piece follows, as it would be without readings
  def curve_on(date) = piece(date)&.curve_on(date) || 0.0

  def curve = @pieces.first.curve

  def thermal? = @pieces.first.thermal?

  # The fit of the latest piece with one (the canopy growing now)
  def fit = @pieces.reverse_each.lazy.filter_map(&:fit).first

  # Readings disagreeing with the curve aren't flagged across cuttings: each piece is short and
  # fitted to its own readings
  def check = nil

  private

  def piece(date) = @pieces.rfind { |piece| piece.emergence_date <= date }
end

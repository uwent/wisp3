require "rails_helper"

RSpec.describe Canopy do
  let(:emergence) { Date.new(2026, 5, 15) }
  let(:end_date) { Date.new(2026, 9, 30) }

  def canopy(observations = [], curve: nil, **)
    described_class.new(emergence_date: emergence, end_date:, observations:, curve:, **)
  end

  it "is 0 everywhere with no readings and no curve" do
    expect(canopy.on(Date.new(2026, 7, 1))).to eq(0.0)
  end

  it "rises from 0 at emergence to the first reading" do
    c = canopy([[Date.new(2026, 5, 25), 20.0]])
    expect(c.on(emergence - 1)).to eq(0.0)
    expect(c.on(emergence)).to eq(0.0)
    expect(c.on(Date.new(2026, 5, 20))).to be_within(1e-9).of(10.0)
    expect(c.on(Date.new(2026, 5, 25))).to eq(20.0)
  end

  it "interpolates between readings, in any order given" do
    c = canopy([[Date.new(2026, 6, 20), 60.0], [Date.new(2026, 6, 10), 40.0]])
    expect(c.on(Date.new(2026, 6, 15))).to be_within(1e-9).of(50.0)
  end

  it "holds the last reading until the end date, then drops to 0 (C3)" do
    c = canopy([[Date.new(2026, 6, 10), 80.0]])
    expect(c.on(Date.new(2026, 6, 17))).to eq(80.0) # legacy: back to 0 after 6 days
    expect(c.on(end_date)).to eq(80.0)
    expect(c.on(end_date + 1)).to eq(0.0)
  end

  it "takes a reading on the emergence date as is" do
    expect(canopy([[emergence, 5.0]]).on(emergence)).to eq(5.0)
  end

  it "ignores readings before emergence" do
    c = canopy([[emergence - 5, 30.0], [Date.new(2026, 5, 25), 20.0]])
    expect(c.on(emergence - 5)).to eq(0.0)
    expect(c.on(Date.new(2026, 5, 20))).to be_within(1e-9).of(10.0)
  end

  describe "the field corn LAI curve (WIS v6.3.11)" do
    let(:curve) { CanopyModel.from("field_corn", emergence) }
    let(:corn) { canopy(curve:, floor: 0.05) }

    it "is 0 before emergence, and absent for a crop without one" do
      expect(CanopyModel.lai("field_corn", -1)).to eq(0.0)
      expect([CanopyModel.lai("soybean", 30), CanopyModel.from("soybean", emergence)]).to eq([nil, nil])
    end

    it "matches the spreadsheet's values by day since emergence" do
      {30 => 0.25, 50 => 1.95, 80 => 4.07, 100 => 3.25, 140 => 0.86}.each do |day, lai|
        expect(CanopyModel.lai("field_corn", day)).to be_within(0.01).of(lai)
      end
    end

    it "is used when there are no readings, from emergence" do
      expect(corn.on(emergence - 1)).to eq(0.0)
      expect(corn.on(emergence + 80)).to be_within(0.01).of(4.07)
    end

    it "is followed through readings, never above the curve's peak or the highest reading" do
      c = canopy([[Date.new(2026, 7, 1), 3.0]], curve:, floor: 0.05)
      expect(c.on(Date.new(2026, 7, 1))).to be_within(1e-9).of(3.0)
      expect(c.on(Date.new(2026, 8, 15))).to be_within(0.01).of(4.07)
    end

    it "is replaced by readings with straight lines" do
      c = canopy([[Date.new(2026, 7, 1), 3.0]], curve:, follow_curve: false)
      expect(c.on(Date.new(2026, 8, 15))).to eq(3.0)
    end
  end

  describe "a percent cover curve" do
    let(:potato) { CanopyCurve.for("potato") }
    let(:curve) { potato.from(emergence) }

    def cover(observations = [], **)
      canopy(observations, curve:, check: true, **)
    end

    it "is followed with no readings, from emergence to the end date" do
      c = cover
      expect(c.on(emergence - 1)).to eq(0.0)
      expect(c.on(emergence + 31)).to be_within(0.1).of(potato.cover(emergence, emergence + 31))
      expect(c.on(end_date + 1)).to eq(0.0)
      expect(c.curve_on(emergence + 31)).to eq(c.on(emergence + 31))
    end

    it "passes through each reading and keeps the curve's shape between and after them" do
      june10, june24 = Date.new(2026, 6, 10), Date.new(2026, 6, 24)
      c = cover([[june10, 40.0], [june24, 85.0]])
      expect(c.on(june10)).to be_within(1e-9).of(40.0)
      expect(c.on(june24)).to be_within(1e-9).of(85.0)
      # The ratio to the curve is interpolated: between them, the curve times a ratio between the two
      ratio = c.on(june10 + 7) / curve.call(june10 + 7)
      expect(ratio).to be_between(40.0 / curve.call(june10), 85.0 / curve.call(june24))
      # After the last reading the ratio is held, so the canopy follows potato's August decline
      expect(c.on(Date.new(2026, 8, 20)) / curve.call(Date.new(2026, 8, 20))).to be_within(1e-9).of(85.0 / curve.call(june24))
      expect(c.on(Date.new(2026, 8, 20))).to be < 85.0
    end

    it "rises from the curve at emergence to the first reading" do
      c = cover([[emergence + 20, 50.0]])
      expect(c.on(emergence)).to be_within(1e-9).of(curve.call(emergence))
      expect(c.on(emergence + 20)).to be_within(1e-9).of(50.0)
    end

    it "takes an early reading's ratio against 1% while the curve is below it" do
      # The curve is 0.7% the day after emergence: 3% against it would be a ratio of 4, not 3
      expect(curve.call(emergence + 1)).to be < 1.0
      c = cover([[emergence + 1, 3.0]])
      expect(c.on(emergence + 20)).to be_within(1e-9).of(3.0 * curve.call(emergence + 20))
    end

    it "never goes above the curve's peak or the highest reading" do
      c = cover([[emergence + 10, 30.0]]) # far ahead of the curve (4% on day 10)
      expect(c.on(emergence + 60)).to be_within(0.01).of(potato.ccx * 100)
    end

    it "draws straight lines when the planting says so" do
      c = cover([[Date.new(2026, 6, 10), 40.0]], follow_curve: false)
      expect(c.on(Date.new(2026, 8, 20))).to eq(40.0)
    end

    describe "vine kill" do
      let(:kill) { Date.new(2026, 8, 20) }

      def killed(observations = [], **) = cover(observations, vine_kill: kill, **)

      it "ramps from the canopy that day down to 0 over two weeks, then stays 0 to the end date" do
        at_kill = cover.on(kill)
        expect(at_kill).to be > 50
        c = killed
        expect(c.on(kill - 1)).to eq(cover.on(kill - 1))
        expect(c.on(kill)).to eq(at_kill)
        expect(c.on(kill + 7)).to be_within(1e-9).of(at_kill / 2)
        expect([c.on(kill + 14), c.on(kill + 20), c.on(end_date)]).to eq([0.0, 0.0, 0.0])
        expect(c.curve_on(kill + 20)).to eq(cover.on(kill + 20)) # the crop's curve is still drawn as is
      end

      it "takes a reading after vine kill as entered, and ramps on from it to the same end" do
        c = killed([[kill + 4, 40.0]])
        expect(c.on(kill + 4)).to eq(40.0)
        expect(c.on(kill + 9)).to be_within(1e-9).of(20.0) # halfway through the 10 days left
        expect(c.on(kill + 14)).to eq(0.0)
        late = killed([[kill + 16, 5.0]]) # green left after the ramp: on its day, then gone
        expect([late.on(kill + 16), late.on(kill + 17)]).to eq([5.0, 0.0])
      end

      it "keeps readings after vine kill out of the living canopy and the check" do
        june10 = Date.new(2026, 6, 10)
        before = killed([[june10, 40.0]])
        with_kill_reading = killed([[june10, 40.0], [kill + 2, 10.0]])
        expect(with_kill_reading.on(kill - 1)).to eq(before.on(kill - 1))
        # A fall from 60% to 40% while the curve still grows is flagged while the canopy lives, but not after
        # vine kill (an early one here, before the curve's decline)
        june17, june22 = Date.new(2026, 6, 17), Date.new(2026, 6, 22)
        expect(curve.call(june22)).to be > curve.call(june17)
        expect(cover([[june17, 60.0], [june22, 40.0]]).check.drop).to be_present
        expect(cover([[june17, 60.0], [june22, 40.0]], vine_kill: june22).check).to be_nil
      end
    end

    describe "#check" do
      it "is nil when the readings follow the curve" do
        readings = [20, 27, 34].map { |day| [emergence + day, potato.cover(emergence, emergence + day)] }
        expect(cover(readings).check).to be_nil
      end

      it "says how many days ahead of the curve the readings run, beyond a week" do
        readings = [12, 18].map { |day| [emergence + day, potato.cover(emergence, emergence + day + 9)] }
        expect(cover(readings).check).to have_attributes(days_ahead: 9, drop: nil)
        behind = [30, 36].map { |day| [emergence + day, potato.cover(emergence, emergence + day - 10)] }
        expect(cover(behind).check.days_ahead).to eq(-10)
      end

      it "notes a reading that fell while the curve was still growing or holding" do
        june10, june17 = Date.new(2026, 6, 10), Date.new(2026, 6, 17)
        expect(cover([[june10, 60.0], [june17, 40.0]]).check.drop).to eq(date: june17, from: 60.0, to: 40.0)
        # In the curve's August decline a fall is expected
        expect(cover([[Date.new(2026, 8, 10), 80.0], [Date.new(2026, 8, 24), 60.0]]).check).to be_nil
      end

      it "isn't run without a curve" do
        expect(canopy([[Date.new(2026, 6, 10), 60.0], [Date.new(2026, 6, 17), 40.0]], check: true).check).to be_nil
      end
    end
  end

  describe ".for" do
    it "takes the crop's percent cover curve and the planting's setting" do
      potato = create(:plant, key: "potato")
      planting = create(:planting, plant: potato, emergence_date: emergence, end_date:)
      expect(described_class.for(planting).on(emergence + 31)).to be > 50
      expect(planting.effective_canopy_interpolation).to eq("curve")

      planting.update!(canopy_interpolation: "linear")
      CanopyObservation.record(planting, Date.new(2026, 6, 10), 40)
      expect(described_class.for(planting.reload).on(Date.new(2026, 8, 20))).to eq(40.0)
    end

    it "takes field corn's LAI curve on the LAI method, with its own floor and no check" do
      corn = create(:plant, :field_corn)
      planting = create(:planting, plant: corn, et_method: "lai", emergence_date: emergence, end_date:)
      expect(described_class.for(planting).on(emergence + 80)).to be_within(0.01).of(4.07)

      # Five days in, the curve is near 0, so a reading's ratio is taken against LAI 0.05
      CanopyObservation.record(planting, emergence + 5, 0.1)
      lai = described_class.for(planting.reload)
      expect(lai.on(emergence + 5)).to be_within(1e-9).of(0.1 / 0.05 * CanopyModel.lai("field_corn", 5))

      # A fall of 20 while the curve grows would be flagged on percent cover
      CanopyObservation.record(planting, emergence + 40, 60)
      CanopyObservation.record(planting, emergence + 47, 40)
      expect(CanopyModel.lai("field_corn", 47)).to be > CanopyModel.lai("field_corn", 40)
      expect(described_class.for(planting.reload).check).to be_nil
    end

    it "takes the planting's vine kill date" do
      planting = create(:planting, plant: create(:plant, key: "potato"), emergence_date: emergence, end_date:,
        vine_kill_date: Date.new(2026, 9, 1))
      expect(described_class.for(planting).on(Date.new(2026, 9, 15))).to eq(0.0)
      expect(described_class.for(planting).on(Date.new(2026, 8, 31))).to be > 40
    end

    it "has no curve for a crop without one" do
      planting = create(:planting, emergence_date: emergence, end_date:)
      expect(described_class.for(planting).on(emergence + 31)).to eq(0.0)
      expect(planting.effective_canopy_interpolation).to eq("linear")
    end
  end
end

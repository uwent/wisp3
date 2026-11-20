require "rails_helper"

RSpec.describe WaterBalance do
  # Sandy loam, 24 in roots, MAD 0.5: TAW 2.4, AD_max 1.2, AD_pwp -1.2, AD = 0 at 10% moisture
  let(:params) do
    WaterBalance::Params.new(field_capacity: 0.15, perm_wilting_pt: 0.05, max_root_zone_depth: 24.0,
      mad_frac: 0.5, et_method: "pct_cover", target_ad_pct: 40)
  end
  let(:start) { Date.new(2026, 6, 1) }

  def day(offset, **inputs)
    WaterBalance::Day.new(date: start + offset, canopy: 100.0, **inputs)
  end

  def run(days, **options) = described_class.run(params, days, **options)

  describe "Params" do
    it "derives the static quantities (§5.1)" do
      expect(params.taw).to be_within(1e-12).of(2.4)
      expect(params.ad_max).to be_within(1e-12).of(1.2)
      expect(params.ad_pwp).to be_within(1e-12).of(-1.2)
      expect(params.pct_at_ad_zero).to be_within(1e-12).of(10.0)
      expect(params.target_in).to be_within(1e-12).of(0.48)
    end

    it "maps moisture to AD and back" do
      expect(params.ad_from_moisture(15.0)).to be_within(1e-12).of(1.2)
      expect(params.ad_from_moisture(5.0)).to be_within(1e-12).of(-1.2)
      expect(params.pct_moisture(0.6)).to be_within(1e-12).of(12.5)
    end

    it "starts at field capacity, or at the initial moisture clamped to the AD range" do
      expect(params.initial_ad).to eq(params.ad_max)
      expect(params.with(initial_moisture_pct: 12.5).initial_ad).to be_within(1e-12).of(0.6)
      expect(params.with(initial_moisture_pct: 30.0).initial_ad).to eq(params.ad_max)
      expect(params.with(initial_moisture_pct: 1.0).initial_ad).to eq(params.ad_pwp)
    end

    it "rejects impossible soils and crops" do
      expect { params.with(perm_wilting_pt: 0.2) }.to raise_error(ArgumentError)
      expect { params.with(max_root_zone_depth: 0) }.to raise_error(ArgumentError)
      expect { params.with(mad_frac: 1.0) }.to raise_error(ArgumentError)
    end
  end

  describe "the daily step (§5.2)" do
    it "subtracts crop ET and adds rain and irrigation" do
      results = run([day(0, et0: 0.3), day(1, et0: 0.2, rain: 0.1, irrigation: 0.05)])
      expect(results.map(&:ad)).to eq([0.9, 0.85])
      expect(results.map(&:adj_et)).to eq([0.3, 0.2])
      expect(results.map(&:pct_moisture)).to eq([13.75, 13.5417])
    end

    it "caps AD at AD_max and records the excess as deep drainage, however small" do
      results = run([day(0, et0: 0.1), day(1, et0: 0.0, rain: 0.105)])
      expect(results.last.ad).to eq(1.2)
      expect(results.last.deep_drainage).to eq(0.005) # legacy zeroed drainage under 0.01
    end

    it "floors AD at the wilting point" do
      results = run([day(0, et0: 0.3)], initial_ad: -1.1)
      expect(results.last.ad).to eq(-1.2)
      expect(results.last.pct_moisture).to eq(5.0)
    end
  end

  describe "soil moisture readings (C2)" do
    it "reset AD from the reading, ignoring that day's water and ET" do
      result = run([day(0, et0: 0.3, rain: 1.0, soil_moisture_pct: 12.5)]).last
      expect(result).to have_attributes(ad: 0.6, deep_drainage: 0.0, moisture_reset: true, adj_et: 0.3)
    end

    it "cap at AD_max with the excess as drainage (legacy capped at TAW)" do
      result = run([day(0, et0: 0.2, soil_moisture_pct: 17.0)]).last
      expect(result.ad).to eq(1.2)
      expect(result.deep_drainage).to eq(0.48)
    end

    it "floor at the wilting point (legacy had no floor)" do
      expect(run([day(0, et0: 0.2, soil_moisture_pct: 2.0)]).last.ad).to eq(-1.2)
    end
  end

  describe "gap fill (§5.4)" do
    it "fills missing et0 with the mean of the top 3 adjusted ETs of the previous 7 days" do
      ets = [0.10, 0.25, 0.20, 0.15, 0.30, 0.05, 0.12, 0.01]
      days = ets.each_with_index.map { |et0, i| day(i, et0:) } + [day(8, et0: nil)]
      filled = run(days).last
      # the previous 7 days are offsets 1..7; their top 3 are 0.30, 0.25, 0.20
      expect(filled).to have_attributes(et_source: :gap_fill, adj_et: 0.25)
    end

    it "doesn't feed filled values back in (C7)" do
      days = [day(0, et0: 0.3), *(1..9).map { |i| day(i, et0: nil) }]
      results = run(days)
      expect(results[1..7].map(&:adj_et)).to all(eq(0.3))
      expect(results[8]).to have_attributes(et_source: :missing, adj_et: nil) # 0.3 is now 8 days back
      expect(results[8].ad).to eq(results[7].ad)
    end

    it "uses earlier history when resuming" do
      result = run([day(0, et0: nil)], et_history: [[start - 1, 0.2], [start - 2, 0.4]]).last
      expect(result.adj_et).to be_within(1e-9).of(0.3)
    end
  end

  describe ".status (§5.5)" do
    it "classifies today's AD" do
      expect(described_class.status(params, 1.1)).to eq(:full)
      expect(described_class.status(params, 0.5)).to eq(:ok)
      expect(described_class.status(params, 0.3)).to eq(:caution)
      expect(described_class.status(params, 0.0)).to eq(:irrigate)
    end

    it "uses half of AD_max without a target" do
      expect(described_class.status(params.with(target_ad_pct: nil), 0.5)).to eq(:caution)
    end
  end

  describe "with a crop: FAO-56's dual crop coefficient (C22)" do
    let(:crop) { WaterBalance::Crop.new(kcb_mid: 1.10, kcb_end: 0.65, height_m: 0.6) }
    # Sand's TEW is (0.15 − 0.025) × 3.94 in = 0.49 in; REW 0.2 in
    let(:params) do
      WaterBalance::Params.new(field_capacity: 0.15, perm_wilting_pt: 0.05, max_root_zone_depth: 24.0, mad_frac: 0.5,
        crop:, rew: 0.2)
    end

    def bare(offset, **inputs) = day(offset, canopy: 0.0, et0: 0.2, **inputs)

    it "evaporates wet bare soil at Kc max, slowing as the surface dries, until rain wets it again" do
      results = run((0..9).map { |i| bare(i, rain: (i == 6) ? 0.5 : 0.0) })
      ets = results.map(&:adj_et)
      expect(ets.first).to be_within(1e-4).of(0.24)
      expect(ets.first(6).each_cons(2)).to all(satisfy { |a, b| b <= a })
      expect(ets[5]).to be < 0.05
      # Kr comes from the day before's depletion, so the rain shows the day after
      expect(ets[7]).to be_within(1e-4).of(0.24)
      expect(results[6].evaporation.depletion).to be < 0.05
    end

    it "wets less of the surface under drip, so less evaporates" do
      dry = SoilEvaporation::State.new(depletion: params.evaporation.tew, fw: 1.0)
      days = (0..5).map { |i| bare(i, irrigation: i.zero? ? 0.3 : 0.0) }
      sprinkled = run(days, evaporation: dry)
      dripped = described_class.run(params.with(irrigation_fw: 0.35), days, evaporation: dry)
      expect(dripped.sum(&:adj_et)).to be < sprinkled.sum(&:adj_et)
      expect(dripped.first.evaporation.fw).to eq(0.35)
    end

    it "resumes from a day's surface layer as if it had run on" do
      days = (0..11).map { |i| bare(i, rain: (i == 2) ? 0.3 : 0.0, canopy: i * 5.0) }
      whole = run(days)
      resumed = run(days.drop(6), initial_ad: whole[5].ad, evaporation: whole[5].evaporation)
      expect(resumed.map(&:adj_et)).to eq(whole.drop(6).map(&:adj_et))
      expect(run(days.drop(6), initial_ad: whole[5].ad).map(&:adj_et)).not_to eq(whole.drop(6).map(&:adj_et))
    end

    it "leaves the surface layer as it was on a soil moisture reading's day and a day without weather" do
      results = run([bare(0), bare(1, soil_moisture_pct: 12.0), bare(2, et0: nil), bare(3)])
      expect(results[1].evaporation).to eq(results[0].evaporation)
      expect(results[1].adj_et).to be > 0
      expect(results[2]).to have_attributes(et_source: :gap_fill, evaporation: results[0].evaporation)
    end

    it "eases Kcb from mid season's to harvest's over the late season (FAO-56 eq. 66)" do
      late = crop.with(late_start: Date.new(2026, 7, 25), end_date: Date.new(2026, 9, 3))
      expect(late.kcb_full(Date.new(2026, 7, 25))).to eq(1.10)
      expect(late.kcb_full(Date.new(2026, 8, 14))).to be_within(1e-12).of(0.875)
      expect(late.kcb_full(Date.new(2026, 9, 3))).to be_within(1e-12).of(0.65)
      expect(crop.kcb_full(Date.new(2026, 9, 3))).to eq(1.10)
      # Eq. 70 adjusts Kcb end only from 0.45
      windy = {wind_mph: 15.0, rh_min_pct: 25.0}
      expect(late.kcb_full(Date.new(2026, 9, 3), **windy)).to be_within(1e-12).of(CropEt.kc_mid(0.65, 0.6, **windy))
      expect(late.with(kcb_end: 0.25).kcb_full(Date.new(2026, 9, 3), **windy)).to be_within(1e-12).of(0.25)
    end

    it "keeps AD in range and conserves water over random seasons" do
      rng = Random.new(7)
      10.times do
        days = 150.times.map do |i|
          WaterBalance::Day.new(date: start + i, et0: (rng.rand < 0.05) ? nil : rng.rand(0.0..0.35),
            rain: (rng.rand < 0.3) ? rng.rand(0.0..1.5) : 0.0, irrigation: (rng.rand < 0.15) ? rng.rand(0.3..1.0) : 0.0,
            canopy: [i * 1.0, 100].min)
        end
        ad = params.initial_ad
        run(days).zip(days).each do |result, input|
          expect(result.ad).to be_between(params.ad_pwp, params.ad_max)
          expect(result.evaporation.depletion).to be_between(0.0, params.evaporation.tew)
          expected = ad + input.rain + input.irrigation - result.adj_et.to_f - result.deep_drainage
          expect(result.ad).to be_within(1e-3).of(expected) unless result.ad <= params.ad_pwp
          ad = result.ad
        end
      end
    end
  end

  describe "properties over random seasons" do
    let(:rng) { Random.new(20261003) }

    def random_season(length = 150)
      length.times.map do |i|
        WaterBalance::Day.new(date: start + i, et0: (rng.rand < 0.05) ? nil : rng.rand(0.0..0.35),
          rain: (rng.rand < 0.3) ? rng.rand(0.0..1.5) : 0.0,
          irrigation: (rng.rand < 0.15) ? rng.rand(0.3..1.0) : 0.0,
          canopy: [i * 1.0, 100].min)
      end
    end

    it "keeps AD between the wilting point and AD_max" do
      20.times do
        expect(run(random_season).map(&:ad)).to all(be_between(params.ad_pwp, params.ad_max))
      end
    end

    it "conserves water: inputs − ET − drainage = change in AD, except where AD hit the wilting point" do
      20.times do
        days = random_season
        ad = params.initial_ad
        run(days).zip(days).each do |result, input|
          expected = ad + input.rain + input.irrigation - result.adj_et.to_f - result.deep_drainage
          expect(result.ad).to be_within(1e-3).of(expected) unless result.ad <= params.ad_pwp
          ad = result.ad
        end
      end
    end
  end
end

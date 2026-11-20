require "rails_helper"

RSpec.describe SoilEvaporation do
  def mm(value) = value / 25.4

  let(:wet) { SoilEvaporation::State.initial }

  it "takes total evaporable water from field capacity and wilting point (FAO-56 eq. 73, Ze 0.10 m)" do
    expect(described_class.tew(0.10, 0.04) * 25.4).to be_within(1e-9).of(8.0) # sand.yml's, Table 19's 6–12 mm
    expect(described_class.tew(0.23, 0.10) * 25.4).to be_within(1e-9).of(18.0) # FAO-56 Example 35
  end

  it "caps readily evaporable water at total" do
    expect(described_class.new(tew: mm(5), rew: mm(9)).rew).to eq(mm(5))
    expect(described_class.new(tew: mm(20), rew: nil).rew).to eq(SoilEvaporation::DEFAULT_REW_IN)
  end

  it "wets drip's share of the surface and sprinklers' and rain's all of it (FAO-56 Table 20)" do
    expect(described_class.wetted_fraction("drip")).to eq(0.35)
    expect(described_class.wetted_fraction("center")).to eq(1.0)
    expect(described_class.wetted_fraction("point")).to eq(1.0)
    expect(described_class.wetted_fraction(nil)).to eq(1.0)
  end

  # Bare loam drying after heavy rain: TEW 20 mm, REW 9 mm, Kcb 0.15, Kc max 1.20, ET0 4.5 mm/day
  it "reproduces FAO-56 Example 31" do
    layer = described_class.new(tew: mm(20), rew: mm(9))
    expected = [[1, 1.05, 4.73], [1, 1.05, 9.45], [0.96, 1.01, 13.98], [0.55, 0.57, 16.57], [0.31, 0.33, 18.04],
      [0.18, 0.19, 18.88], [0.10, 0.11, 19.36], [0.06, 0.06, 19.64], [0.03, 0.03, 19.79], [0.02, 0.02, 19.88]]
    state = wet
    expected.each do |_kr, ke, depletion|
      step = layer.step(state, et0: mm(4.5), kcb: 0.15, kc_max: 1.20, cover: 0.0)
      expect(step.ke).to be_within(0.006).of(ke)
      expect(step.state.depletion * 25.4).to be_within(0.02).of(depletion)
      state = step.state
    end
  end

  # Cotton at 53% cover, Kcb 0.90, Kc max 1.30, the surface just wetted
  it "limits Ke to the exposed, wetted share of the surface (FAO-56 Examples 32 and 33)" do
    layer = described_class.new(tew: mm(20), rew: mm(9))
    sprinkler = layer.step(wet, et0: mm(7), kcb: 0.90, kc_max: 1.30, cover: 0.53, irrigation: mm(30))
    expect(sprinkler.ke).to be_within(0.005).of(0.40)
    furrow = layer.step(wet, et0: mm(7), kcb: 0.90, kc_max: 1.30, cover: 0.53, irrigation: mm(30), irrigation_fw: 0.3)
    expect(furrow.ke).to be_within(0.005).of(0.39)
    expect(furrow.state.fw).to eq(0.3)
  end

  describe "wetting" do
    let(:layer) { described_class.new(tew: mm(8), rew: mm(4.5)) }
    let(:dry) { SoilEvaporation::State.new(depletion: mm(8), fw: 1.0) }

    def step(state, **inputs) = layer.step(state, et0: mm(5), kcb: 0.0, kc_max: 1.2, cover: 0.0, **inputs)

    it "takes Kr from the day before's depletion, then the day's wetting (eq. 74's De,i−1)" do
      soaked = step(dry, rain: mm(25))
      expect(soaked.ke).to eq(0.0)
      expect(soaked.state.depletion).to eq(0.0)
      expect(step(soaked.state).ke).to eq(1.2)
    end

    it "wets drip's share of the surface, deeper, and keeps it until the next wetting" do
      dripped = step(dry, irrigation: mm(1.4), irrigation_fw: 0.35)
      expect(dripped.state.fw).to eq(0.35)
      # 1.4 mm over 35% of the field is 4 mm on the wetted part
      expect(dripped.state.depletion).to be_within(1e-9).of(mm(4))
      expect(step(dripped.state).state.fw).to eq(0.35)
      expect(step(dripped.state, rain: mm(1)).state.fw).to eq(0.35) # under WETTING_RAIN_IN
      expect(step(dripped.state, irrigation: mm(1)).state.fw).to eq(1.0) # a sprinkler's
      expect(step(dripped.state, rain: mm(3), irrigation: mm(1)).state.fw).to eq(1.0)
    end

    it "keeps depletion between 0 and TEW" do
      state = wet
      20.times { state = step(state).state }
      expect(state.depletion).to be_within(1e-12).of(mm(8))
    end

    it "evaporates nothing more under a closed canopy than its 1% gap allows" do
      shaded = layer.step(wet, et0: mm(5), kcb: 1.1, kc_max: 1.2, cover: 1.0)
      expect(shaded.ke).to be_within(1e-12).of(0.012)
    end
  end
end

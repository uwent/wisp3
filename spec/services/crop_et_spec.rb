require "rails_helper"

RSpec.describe CropEt do
  describe ".from_pct_cover" do
    it "is 0 without reference ET" do
      expect(described_class.from_pct_cover(0.0, 50)).to eq(0.0)
    end

    it "equals reference ET at 80% cover and above" do
      expect(described_class.from_pct_cover(0.25, 80)).to eq(0.25)
      expect(described_class.from_pct_cover(0.25, 100)).to eq(0.25)
    end

    it "uses each band's regression at its 10% step" do
      CropEt::PCT_COVER_COEFFICIENTS.first(7).each.with_index(1) do |(intercept, slope), step|
        expect(described_class.from_pct_cover(0.2, step * 10)).to be_within(1e-12).of(intercept + 0.2 * slope)
      end
    end

    it "interpolates linearly within a band" do
      low = described_class.from_pct_cover(0.2, 30)
      high = described_class.from_pct_cover(0.2, 40)
      expect(described_class.from_pct_cover(0.2, 35)).to be_within(1e-12).of((low + high) / 2)
    end

    it "is continuous across band boundaries" do
      (10..80).step(10).each do |boundary|
        below = described_class.from_pct_cover(0.2, boundary - 1e-9)
        expect(described_class.from_pct_cover(0.2, boundary)).to be_within(1e-8).of(below)
      end
    end

    it "uses half-open bare-soil steps (C8)" do
      expect(described_class.from_pct_cover(0.159, 0)).to eq(0.0)
      expect(described_class.from_pct_cover(0.1595, 0)).to eq(0.0) # legacy: 0.02
      expect(described_class.from_pct_cover(0.16, 0)).to eq(0.01)
      expect(described_class.from_pct_cover(0.3195, 0)).to eq(0.01) # legacy: 0.02
      expect(described_class.from_pct_cover(0.32, 0)).to eq(0.02)
    end

    it "clamps cover to 0–100 (C8: legacy treated negative cover as full cover)" do
      expect(described_class.from_pct_cover(0.25, -5)).to eq(described_class.from_pct_cover(0.25, 0))
      expect(described_class.from_pct_cover(0.25, 120)).to eq(0.25)
    end

    it "never goes negative at very low reference ET" do
      expect(described_class.from_pct_cover(0.005, 10)).to eq(0.0)
    end

    it "increases with cover" do
      values = (0..100).map { |cover| described_class.from_pct_cover(0.22, cover) }
      expect(values.each_cons(2)).to all(satisfy { |a, b| b >= a })
    end
  end

  describe ".from_lai" do
    it "applies Kc = 1.1 × (1 − e^(−1.5·LAI))" do
      expect(described_class.from_lai(0.2, 2.0)).to be_within(1e-12).of(0.2 * 1.1 * (1 - Math.exp(-3.0)))
    end

    it "is 0 at LAI 0, tends to 1.1 × et0, and treats negative LAI as 0" do
      expect(described_class.from_lai(0.2, 0)).to eq(0.0)
      expect(described_class.from_lai(0.2, 20)).to be_within(1e-9).of(0.22)
      expect(described_class.from_lai(0.2, -1)).to eq(0.0)
    end
  end

  it "rejects an unknown method" do
    expect { described_class.adjusted("kc", 0.2, 1) }.to raise_error(ArgumentError)
  end
end

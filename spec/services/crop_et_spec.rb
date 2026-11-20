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

    it "is 0 without reference ET" do
      expect(described_class.from_lai(0.0, 3.0)).to eq(0.0)
    end

    it "is 0 at LAI 0, tends to 1.1 × et0, and treats negative LAI as 0" do
      expect(described_class.from_lai(0.2, 0)).to eq(0.0)
      expect(described_class.from_lai(0.2, 20)).to be_within(1e-9).of(0.22)
      expect(described_class.from_lai(0.2, -1)).to eq(0.0)
    end
  end

  describe "with the crop's Kc mid (C21)" do
    it "scales the table from 1 on bare soil to Kc mid at 80% cover and above" do
      expect(described_class.from_pct_cover(0.3, 0, kc: 1.15)).to eq(described_class.from_pct_cover(0.3, 0))
      expect(described_class.from_pct_cover(0.25, 80, kc: 1.15)).to be_within(1e-12).of(0.25 * 1.15)
      expect(described_class.from_pct_cover(0.25, 100, kc: 1.15)).to be_within(1e-12).of(0.25 * 1.15)
      expect(described_class.from_pct_cover(0.2, 40, kc: 1.15))
        .to be_within(1e-12).of(described_class.from_pct_cover(0.2, 40) * 1.075)
    end

    it "lowers crop ET at full cover for a Kc mid below 1" do
      expect(described_class.from_pct_cover(0.2, 90, kc: 0.95)).to be_within(1e-12).of(0.19)
    end

    it "still increases with cover" do
      values = (0..100).map { |cover| described_class.from_pct_cover(0.22, cover, kc: 1.2) }
      expect(values.each_cons(2)).to all(satisfy { |a, b| b >= a })
    end

    it "tops LAI's Kc out at Kc mid" do
      expect(described_class.from_lai(0.2, 20, kc: 1.2)).to be_within(1e-9).of(0.24)
      expect(described_class.adjusted("lai", 0.2, 2.0, kc: 1.2)).to be_within(1e-12).of(0.2 * 1.2 * (1 - Math.exp(-3.0)))
    end
  end

  describe ".kc_mid (FAO-56 eq. 62)" do
    # u2 in m/s at 2 m → stored wind, mph at 10 m
    def mph(u2) = u2 / (4.87 / Math.log(67.8 * 10 - 5.42)) / CropEt::MPH_TO_MS

    it "matches FAO-56 Example 27 (maize, Kc mid 1.20, 2 m)" do
      expect(described_class.kc_mid(1.2, 2.0, wind_mph: mph(1.3), rh_min_pct: 75)).to be_within(0.005).of(1.07)
      expect(described_class.kc_mid(1.2, 2.0, wind_mph: mph(4.6), rh_min_pct: 44)).to be_within(0.005).of(1.30)
    end

    it "is the table value in the standard climate, or with no weather" do
      expect(described_class.kc_mid(1.15, 0.6, wind_mph: mph(2.0), rh_min_pct: 45)).to be_within(1e-9).of(1.15)
      expect(described_class.kc_mid(1.15, 0.6)).to eq(1.15)
    end

    it "clamps wind to 1–6 m/s and minimum humidity to 20–80%" do
      expect(described_class.kc_mid(1.15, 0.6, wind_mph: mph(12), rh_min_pct: 5))
        .to be_within(1e-9).of(described_class.kc_mid(1.15, 0.6, wind_mph: mph(6), rh_min_pct: 20))
      expect(described_class.kc_mid(1.15, 0.6, wind_mph: 0.0, rh_min_pct: 100))
        .to be_within(1e-9).of(described_class.kc_mid(1.15, 0.6, wind_mph: mph(1), rh_min_pct: 80))
    end

    it "isn't applied below 0.1 m" do
      expect(described_class.kc_mid(1.05, 0.05, wind_mph: 20, rh_min_pct: 20)).to eq(1.05)
    end
  end

  describe "the dual crop coefficient's basal Kcb (C22)" do
    def mph(u2) = u2 / (4.87 / Math.log(67.8 * 10 - 5.42)) / CropEt::MPH_TO_MS

    it "is 0 on bare soil and the full-cover Kcb under a closed canopy (FAO-56 eq. 98)" do
      expect(described_class.kcb_from_cover(1.1, 0, 0.6)).to eq(0.0)
      expect(described_class.kcb_from_cover(1.1, 100, 0.6)).to be_within(1e-12).of(1.1)
      expect(described_class.kcb_from_cover(1.1, 120, 0.6)).to be_within(1e-12).of(1.1)
    end

    it "rises with cover by its effective shade, Kd = min(1, 2·fc, fc^(1/(1+h)))" do
      # 10% cover: fc^(1/(1 + 0.06)) = 0.114; 50%: fc^(1/(1 + 0.3)) = 0.587
      expect(described_class.kcb_from_cover(1.1, 10, 0.6)).to be_within(1e-9).of(0.15 + 0.1**(1 / 1.06) * 0.95)
      expect(described_class.kcb_from_cover(1.1, 50, 0.6)).to be_within(1e-9).of(0.15 + 0.5**(1 / 1.3) * 0.95)
      values = (1..100).map { |cover| described_class.kcb_from_cover(1.1, cover, 0.6) }
      expect(values.each_cons(2)).to all(satisfy { |low, high| high >= low })
    end

    it "follows leaf area by FAO-56 eq. 97" do
      expect(described_class.kcb_from_lai(1.15, 0)).to eq(0.0)
      expect(described_class.kcb_from_lai(1.15, 3)).to be_within(1e-12).of(0.15 + 1.0 * (1 - Math.exp(-2.1)))
      expect(described_class.cover_fraction("lai", 3)).to be_within(1e-12).of(1 - Math.exp(-2.1))
      expect(described_class.cover_fraction("pct_cover", 40)).to eq(0.4)
      expect(described_class.kcb("lai", 1.15, 3, 2.0)).to eq(described_class.kcb_from_lai(1.15, 3))
    end

    it "takes Kc max from eq. 72 (FAO-56 Example 32: cotton, u2 3 m/s, RHmin 20%, 1 m)" do
      expect(described_class.kc_max(0.9, 1.0, wind_mph: mph(3), rh_min_pct: 20)).to be_within(0.005).of(1.30)
      expect(described_class.kc_max(1.2, 0.6)).to be_within(1e-12).of(1.25)
    end
  end

  it "rejects an unknown method" do
    expect { described_class.adjusted("kc", 0.2, 1) }.to raise_error(ArgumentError)
  end
end

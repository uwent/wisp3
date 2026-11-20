require "rails_helper"

# upsert_all skips validations, so check the YAML's rows against the models here
RSpec.describe ReferenceData do
  it "loads plants and soil types that pass their validations" do
    described_class.load!
    expect(Plant.count).to be > 30
    expect(Plant.all.reject(&:valid?).map(&:key)).to be_empty
    expect(SoilType.all.reject(&:valid?).map(&:key)).to be_empty
  end

  it "gives every crop FAO-56 Table 12's Kc mid and height (C21)" do
    described_class.load!
    expect(Plant.where(kc_mid: nil).or(Plant.where(crop_height_m: nil))).to be_empty
    expect(Plant.find_by!(key: "potato")).to have_attributes(kc_mid: 1.15, crop_height_m: 0.6)
    expect(Plant.find_by!(key: "field_corn")).to have_attributes(kc_mid: 1.2, crop_height_m: 2.0)
  end

  it "gives every crop FAO-56 Table 17's Kcb mid and end, and every soil Table 19's REW (C22)" do
    described_class.load!
    expect(Plant.where(kcb_mid: nil).or(Plant.where(kcb_end: nil))).to be_empty
    expect(Plant.find_by!(key: "potato")).to have_attributes(kcb_mid: 1.10, kcb_end: 0.65)
    expect(Plant.find_by!(key: "field_corn")).to have_attributes(kcb_mid: 1.15, kcb_end: 0.5)
    expect(SoilType.where(rew_in: nil)).to be_empty
    expect(SoilType.find_by!(key: "sand").rew_in * 25.4).to be_within(0.05).of(4.5)
  end
end

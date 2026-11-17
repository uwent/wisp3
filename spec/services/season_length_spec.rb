require "rails_helper"

# PLAN.md Phase 8 G.7: the crops added (dry bean, corn silage, oats, sugar beet, sorghum), and a
# planting's own season length, which stretches its crop's canopy curve in time.
RSpec.describe "Season length and the G.7 crops" do
  let(:emergence) { Date.new(2026, 5, 15) }
  let(:field) { create(:field) }

  def planting_of(key, canopy_model: nil, **attributes)
    plant = Plant.find_by(key:) || create(:plant, key:, name: key.humanize, canopy_model:)
    create(:planting, field:, plant:, emergence_date: emergence, end_date: Date.new(2026, 11, 30), **attributes)
  end

  def day_reaching(curve, cover) = (0..200).find { |day| curve.cover(emergence, emergence + day) >= cover }

  it "gives each new crop a curve with a typical season" do
    {"dry_bean" => [31, 109], "corn_silage" => [29, 102], "oats" => [25, 100], "sugar_beet" => [46, 138],
     "sorghum" => [30, 89]}.each do |key, (half, season)|
      curve = CanopyCurve.for(key)
      expect(day_reaching(curve, 50)).to eq(half), key
      expect(curve.season_days).to eq(season), key
    end
  end

  it "runs corn silage on field corn's curve, LAI included, harvested earlier" do
    expect(CanopyCurve.for("corn_silage").from(emergence).call(emergence + 60))
      .to eq(CanopyCurve.for("field_corn").from(emergence).call(emergence + 60))
    silage = planting_of("corn_silage", canopy_model: "field_corn", et_method: "lai")
    expect(silage).to be_valid
    expect(Canopy.for(silage).on(emergence + 80)).to be_within(0.01).of(CanopyModel.lai("field_corn", 80))
  end

  it "declines dry beans to maturity, unlike snap beans harvested green" do
    curve = CanopyCurve.for("dry_bean")
    expect(curve.cover(emergence, emergence + 60)).to be > 95
    expect(curve.cover(emergence, emergence + 100)).to be < 50
  end

  it "stretches the crop's whole curve by the planting's season over the typical one" do
    oats = planting_of("oats", season_days: 125)
    expect(oats.time_stretch).to eq(1.25)
    curve = CanopyCurve.for("oats")
    canopy = Canopy.for(oats)
    # Growth and decline: day 50 now looks like the typical day 40, day 120 like day 96
    expect(canopy.on(emergence + 50)).to be_within(0.01).of(curve.cover(emergence, emergence + 40))
    expect(canopy.on(emergence + 120)).to be_within(0.01).of(curve.cover(emergence, emergence + 96))
    expect(oats.effective_season_days).to eq(125)
  end

  it "stretches the LAI curve too" do
    corn = planting_of("field_corn", canopy_model: "field_corn", et_method: "lai", season_days: 113)
    expect(Canopy.for(corn).on(emergence + 72)).to be_within(0.01).of(CanopyModel.lai("field_corn", 72 * 126 / 113.0))
  end

  it "fits readings around the stretched curve" do
    oats = planting_of("oats", season_days: 125)
    curve = CanopyCurve.for("oats")
    # Readings on the stretched curve need no fit
    [30, 45].each do |day|
      create(:canopy_observation, planting: oats, date: emergence + day, pct_cover: curve.cover(emergence, emergence + day, stretch: 1.25))
    end
    expect(Canopy.for(oats.reload).fit).to be_typical
  end

  it "has no season length of its own without a curve season, and leaves none behind" do
    oats = planting_of("oats", season_days: 90)
    alfalfa = create(:plant, key: "alfalfa", name: "Alfalfa")
    oats.update!(plant: alfalfa)
    expect(oats.reload.season_days).to be_nil
    expect(oats.time_stretch).to eq(1.0)
    expect(oats.effective_season_days).to be_nil
  end

  it "suggests the harvest from the planting's season" do
    oats = Plant.find_by(key: "oats") || create(:plant, key: "oats", name: "Oats")
    expect(Planting.typical_end(oats, emergence)).to eq(emergence + 100)
    expect(Planting.typical_end(oats, emergence, nil, 120)).to eq(emergence + 120)
  end

  it "rejects a season length out of range" do
    expect(planting_of("oats").tap { |p| p.season_days = 10 }).not_to be_valid
  end
end

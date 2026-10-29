require "rails_helper"

RSpec.describe "Domain models" do
  describe Planting do
    let(:field) { create(:field) }
    let(:first) { create(:planting, field:, season_start: Date.new(2026, 4, 1), end_date: Date.new(2026, 7, 15)) }

    it "uses LAI only for a crop with an LAI growth curve" do
      create(:plant, name: "Field Corn", canopy_model: "field_corn")
      planting = build(:planting, field:, et_method: "lai")
      expect(planting).not_to be_valid
      expect(planting.errors[:et_method].sole).to include("(Field Corn)")
      planting.plant = create(:plant, canopy_model: "field_corn")
      expect(planting).to be_valid
    end

    it "can't overlap another planting on the field" do
      first
      overlapping = build(:planting, field:, season_start: Date.new(2026, 7, 15), emergence_date: Date.new(2026, 7, 20),
        end_date: Date.new(2026, 9, 30))
      expect(overlapping).not_to be_valid
      expect(overlapping.errors[:season_start]).to include("overlaps another planting on this field")
    end

    it "is also kept from overlapping by the database" do
      first
      overlapping = build(:planting, field:, season_start: Date.new(2026, 7, 1), emergence_date: Date.new(2026, 7, 20),
        end_date: Date.new(2026, 9, 30))
      expect { overlapping.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /plantings_no_overlap/)
    end

    it "allows a second crop after the first (double cropping)" do
      first
      second = create(:planting, field:, season_start: Date.new(2026, 7, 16), emergence_date: Date.new(2026, 7, 25),
        end_date: Date.new(2026, 10, 15))
      expect(field.planting_on(Date.new(2026, 6, 1))).to eq(first)
      expect(field.planting_on(Date.new(2026, 8, 1))).to eq(second)
    end

    it "allows emergence before the season start (perennials) but not after the end" do
      expect(build(:planting, emergence_date: Date.new(2025, 5, 1))).to be_valid
      expect(build(:planting, emergence_date: Date.new(2026, 10, 1))).not_to be_valid
    end

    it "takes a vine kill date between emergence and harvest, for potato only" do
      potato = create(:plant, key: "potato")
      planting = build(:planting, plant: potato, emergence_date: Date.new(2026, 5, 15), end_date: Date.new(2026, 9, 30))
      expect(planting.tap { |p| p.vine_kill_date = Date.new(2026, 9, 10) }).to be_valid
      expect(planting.tap { |p| p.vine_kill_date = Date.new(2026, 10, 1) }.tap(&:validate).errors[:vine_kill_date])
        .to eq(["must be on or before the harvest date"])
      expect(planting.tap { |p| p.vine_kill_date = Date.new(2026, 5, 1) }.tap(&:validate).errors[:vine_kill_date])
        .to eq(["must be on or after emergence"])

      # Another crop keeps none, so changing the crop leaves none behind
      planting.update!(vine_kill_date: Date.new(2026, 9, 10))
      planting.update!(plant: create(:plant, key: "onion"))
      expect(planting.reload.vine_kill_date).to be_nil
    end

    it "is kept to a vine kill date inside the season by the database too" do
      planting = create(:planting, plant: create(:plant, key: "potato"), end_date: Date.new(2026, 9, 30))
      expect { planting.update_columns(vine_kill_date: Date.new(2026, 10, 15)) }
        .to raise_error(ActiveRecord::StatementInvalid, /plantings_vine_kill_order/)
    end

    it "ends on or after the season start" do
      planting = build(:planting, season_start: Date.new(2026, 4, 1), emergence_date: Date.new(2026, 3, 1),
        end_date: Date.new(2026, 3, 15))
      expect(planting).not_to be_valid
      expect(planting.errors.of_kind?(:end_date, "must be on or after the season start")).to be(true)
    end

    it "has a canopy curve by its method: percent cover for crops in canopy_curves.yml, LAI for field corn" do
      corn = create(:plant, :field_corn)
      expect(build(:planting, plant: corn, et_method: "lai")).to have_attributes(canopy_curve?: true,
        effective_canopy_interpolation: "curve")
      expect(build(:planting, plant: create(:plant, key: "soybean"), et_method: "lai").canopy_curve?).to be(false)
      expect(build(:planting, plant: create(:plant, key: "onion"))).to have_attributes(canopy_curve?: false,
        effective_canopy_interpolation: "linear")
    end

    it "has legacy-style defaults" do
      plant = build(:plant, default_max_root_zone_depth: 16)
      expect(described_class.defaults_for(plant, 2027)).to include(season_start: Date.new(2027, 4, 1),
        end_date: Date.new(2027, 11, 30), max_root_zone_depth: 16, mad_frac: 0.5)
    end
  end

  describe Field do
    it "falls back to the soil type's water fractions when its own are NULL (C14)" do
      field = build(:field, soil_type: build(:soil_type, field_capacity: 0.24, perm_wilting_pt: 0.08))
      expect([field.effective_field_capacity, field.effective_perm_wilting_pt]).to eq([0.24, 0.08])
      field.perm_wilting_pt = 0.3
      expect(field).not_to be_valid
    end
  end

  describe Pivot do
    it "needs a location in the US or Canada" do
      expect(build(:pivot, latitude: nil)).not_to be_valid
      expect(build(:pivot, longitude: 89.5)).not_to be_valid # sign dropped
      expect(build(:pivot, latitude: -89.5, longitude: 44.5)).not_to be_valid # swapped
      expect(build(:pivot, latitude: 44.5, longitude: -89.5)).to be_valid # Wisconsin
      expect(build(:pivot, latitude: 36.7, longitude: -119.8)).to be_valid # California
      expect(build(:pivot, latitude: 50.4, longitude: -104.6)).to be_valid # Saskatchewan
    end

    it "is no larger than the longest center pivots" do
      expect(build(:pivot, radius_ft: 3000)).to be_valid
      pivot = build(:pivot, radius_ft: 3001)
      expect(pivot).not_to be_valid
      expect(pivot.errors[:radius_ft].sole).to include("longer than any center pivot")
    end

    it "is a linear move with its length, travel and direction, within a machine's size" do
      linear = ->(**shape) { build(:pivot, kind: "linear", length_ft: 1300, travel_ft: 2640, travel_bearing_deg: 0, **shape) }
      expect(linear.call).to be_valid
      expect(linear.call(length_ft: 3300, travel_ft: 5280, travel_bearing_deg: 179)).to be_valid
      expect(linear.call(travel_ft: nil)).not_to be_valid
      expect(linear.call(travel_bearing_deg: nil)).not_to be_valid
      expect(linear.call(length_ft: 3400).tap(&:validate).errors.attribute_names).to eq([:length_ft])
      expect(linear.call(travel_ft: 6000).tap(&:validate).errors.attribute_names).to eq([:travel_ft])
      expect(linear.call(travel_bearing_deg: 180)).not_to be_valid # the same line as 0
      expect(linear.call(travel_bearing_deg: "30.5")).not_to be_valid # whole degrees
      expect(build(:pivot, kind: "lateral")).not_to be_valid
    end

    it "needs both ends of an arc" do
      expect(build(:pivot, arc_start_deg: 30, arc_end_deg: nil).tap(&:validate).errors.attribute_names).to eq([:arc_end_deg])
      expect(build(:pivot, arc_start_deg: nil, arc_end_deg: 300).tap(&:validate).errors.attribute_names).to eq([:arc_start_deg])
      expect(build(:pivot, arc_start_deg: 30, arc_end_deg: 300)).to be_valid
    end

    it "keeps only its own kind's dimensions" do
      pivot = create(:pivot, radius_ft: 1300, arc_start_deg: 30, arc_end_deg: 300)
      pivot.update!(kind: "linear", length_ft: 1300, travel_ft: 2640, travel_bearing_deg: 30)
      expect(pivot.reload).to have_attributes(radius_ft: nil, arc_start_deg: nil, arc_end_deg: nil)
      pivot.update!(kind: "center", radius_ft: 1300)
      expect(pivot.reload).to have_attributes(length_ft: nil, travel_ft: nil, travel_bearing_deg: nil)
    end

    it "is held to its shape in the database too" do
      pivot = create(:pivot)
      write = ->(changes) { Pivot.transaction(requires_new: true) { pivot.update_columns(changes) } }
      expect { write.call(radius_ft: 5000) }.to raise_error(ActiveRecord::StatementInvalid, /pivots_radius_max/)
      expect { write.call(kind: "linear") }.to raise_error(ActiveRecord::StatementInvalid, /pivots_linear_shape/)
    end
  end

  describe CanopyObservation do
    it "takes percent cover or LAI, not both" do
      expect(build(:canopy_observation, pct_cover: 40, lai: 2)).not_to be_valid
      expect(build(:canopy_observation, pct_cover: nil, lai: 2)).to be_valid
      expect(build(:canopy_observation, pct_cover: 140)).not_to be_valid
    end
  end

  describe PivotIrrigation do
    let(:pivot) { create(:pivot) }
    let!(:field) { create(:field, pivot:) }

    it "needs inches or run hours" do
      expect(build(:pivot_irrigation, pivot:, inches: nil)).not_to be_valid
    end

    it "needs pump capacity and areas to use run hours" do
      expect(build(:pivot_irrigation, pivot:, inches: nil, run_hours: 8)).not_to be_valid
      pivot.update!(pump_capacity_gpm: 800)
      expect(build(:pivot_irrigation, pivot:, inches: nil, run_hours: 8)).to be_valid
    end

    it "only applies to fields under the pivot" do
      expect(build(:pivot_irrigation, pivot:, field_ids: [create(:field).id])).not_to be_valid
      expect(build(:pivot_irrigation, pivot:, field_ids: [field.id])).to be_valid
    end
  end

  describe FieldGroupMember do
    it "can't add another account's field" do
      field_group = create(:field_group)
      expect(field_group.field_group_members.build(field: create(:field))).not_to be_valid
    end
  end

  describe Group do
    it "reaches its plantings, and only its own" do
      planting = create(:planting)
      create(:planting)
      expect(planting.field.farm.group.plantings).to eq([planting])
    end
  end

  describe ReferenceData do
    it "loads plants and soil types, and can run again" do
      2.times { described_class.load! }
      expect(Plant.count).to eq(27)
      expect(SoilType.count).to eq(11)
      expect(Plant.find_by(key: "field_corn").canopy_model).to eq("field_corn")
      expect(SoilType.default.field_capacity).to eq(0.17)
    end
  end
end

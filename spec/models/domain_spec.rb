require "rails_helper"

RSpec.describe "Domain models" do
  describe Planting do
    let(:field) { create(:field) }
    let(:first) { create(:planting, field:, season_start: Date.new(2026, 4, 1), end_date: Date.new(2026, 7, 15)) }

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
    it "needs a location in or near Wisconsin" do
      expect(build(:pivot, latitude: nil)).not_to be_valid
      expect(build(:pivot, longitude: 89.5)).not_to be_valid # sign dropped
      expect(build(:pivot, latitude: 44.5, longitude: -89.5)).to be_valid
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
      expect(SoilType.count).to eq(7)
      expect(Plant.find_by(key: "field_corn").canopy_model).to eq("field_corn")
      expect(SoilType.default.field_capacity).to eq(0.15)
    end
  end
end

require "rails_helper"

# A field's outline (PLAN.md Phase 8 G.10; one ring since G.14). The same polygons and areas are in lib/geo.test.ts.
RSpec.describe FieldBoundary do
  # 0.01° on a side at 43.3°N: 1,112 m north–south by 809 m east–west, about 222 acres
  let(:outer) { [[-89.35, 43.3], [-89.34, 43.3], [-89.34, 43.31], [-89.35, 43.31], [-89.35, 43.3]] }
  let(:hole) { [[-89.348, 43.302], [-89.348, 43.304], [-89.346, 43.304], [-89.346, 43.302], [-89.348, 43.302]] }
  let(:square) { {"type" => "Polygon", "coordinates" => [outer]} }

  def ring(corners, center: [-89.4, 43.3], radius: 0.001)
    points = (0...corners).map do |i|
      angle = 2 * Math::PI * i / corners
      [center[0] + radius * Math.cos(angle), center[1] + radius * Math.sin(angle)]
    end
    points + [points.first]
  end

  describe ".acres" do
    it "measures a polygon on a spherical earth" do
      expect(described_class.acres(square)).to be_within(0.01).of(222.338)
    end

    it "measures it whichever way its ring winds" do
      reversed = {"type" => "Polygon", "coordinates" => [outer.reverse]}
      expect(described_class.acres(reversed)).to be_within(0.01).of(222.338)
    end
  end

  describe ".errors" do
    it "accepts a field-sized polygon" do
      expect(described_class.errors(square)).to be_empty
    end

    it "wants a polygon" do
      expect(described_class.errors({"type" => "Point", "coordinates" => [-89.3, 43.3]})).to eq(["must be a polygon"])
      expect(described_class.errors({"type" => "MultiPolygon", "coordinates" => [[outer]]})).to eq(["must be a polygon"])
      expect(described_class.errors("nonsense")).to eq(["must be a polygon"])
    end

    it "wants one shape without holes" do
      expect(described_class.errors({"type" => "Polygon", "coordinates" => [outer, hole]}))
        .to eq(["must be one shape without holes"])
    end

    it "wants a closed ring of at least three corners" do
      expect(described_class.errors({"type" => "Polygon", "coordinates" => [outer[0..3]]})).to eq(["isn't closed"])
      expect(described_class.errors({"type" => "Polygon", "coordinates" => [outer[0..1] + [outer[0]]]}))
        .to eq(["has fewer than 3 corners"])
    end

    it "allows at most MAX_VERTICES corners" do
      expect(described_class.errors({"type" => "Polygon", "coordinates" => [ring(1000)]})).to be_empty
      expect(described_class.errors({"type" => "Polygon", "coordinates" => [ring(1001)]}))
        .to eq(["has too many corners (at most 1,000; simplify it)"])
    end

    it "wants it in the US or Canada" do
      europe = outer.map { |lng, lat| [-lng, lat] }
      expect(described_class.errors({"type" => "Polygon", "coordinates" => [europe]})).to eq(["must be in the US or Canada"])
    end

    it "wants a field's size" do
      tiny = {"type" => "Polygon", "coordinates" => [ring(4, radius: 0.00001)]}
      expect(described_class.errors(tiny)).to eq(["is too small (at least 0.01 acres)"])
      huge = {"type" => "Polygon", "coordinates" => [ring(8, radius: 0.05)]}
      expect(described_class.errors(huge)).to eq(["is larger than a field (at most 1,500 acres)"])
    end
  end

  describe ".normalize" do
    it "parses JSON, rounds to about a centimeter and drops altitudes" do
      json = {type: "Polygon", coordinates: [[[-89.123456789, 43.3, 250], [-89.1, 43.3], [-89.1, 43.31], [-89.123456789, 43.3, 250]]]}.to_json
      expect(described_class.normalize(json)).to eq({"type" => "Polygon",
        "coordinates" => [[[-89.1234568, 43.3], [-89.1, 43.3], [-89.1, 43.31], [-89.1234568, 43.3]]]})
    end

    it "leaves what it can't read for errors to describe" do
      expect(described_class.normalize("{not json")).to eq("{not json")
      odd = {"type" => "Polygon", "coordinates" => [[["a", "b"]]]}
      expect(described_class.normalize(odd)).to eq(odd)
      multi = {"type" => "MultiPolygon", "coordinates" => [[outer]]}
      expect(described_class.normalize(multi)).to eq(multi)
    end
  end

  describe "on a field" do
    let(:field) { create(:field, area_acres: 200) }

    it "stores an outline given as JSON and offers its acres without changing the field's area" do
      field.update!(boundary: square.to_json)
      expect(field.reload.boundary).to eq(square)
      expect(field.boundary_acres).to be_within(0.01).of(222.338)
      expect(field.area_acres).to eq(200)
    end

    it "clears the outline when given blank" do
      field.update!(boundary: square)
      field.update!(boundary: "")
      expect(field.reload.boundary).to be_nil
      expect(field.boundary_acres).to be_nil
    end

    it "refuses an outline that isn't one, saying why" do
      expect(field.update(boundary: "{not json")).to be(false)
      expect(field.errors[:boundary]).to eq(["must be a polygon"])
    end

    it "leaves open plantings' area alone when the outline changes" do
      planting = create(:planting, field:)
      field.update!(boundary: square)
      expect(planting.reload.area_acres).to eq(200)
    end
  end
end

require "rails_helper"

# Constants the frontend repeats from Ruby, read from its source so the two can't drift apart
RSpec.describe "Constants mirrored in the frontend" do
  def frontend_constant(file, name)
    source = Rails.root.join("app/frontend/lib", file).read
    value = source[/^export const #{name} = (-?\d+(?:\.\d+)?)$/, 1] or raise "#{name} not found in #{file}"
    value.include?(".") ? value.to_f : value.to_i
  end

  it "has the pivot size limits of Pivot in lib/geo.ts" do
    %i[MAX_RADIUS_FT MAX_LINEAR_LENGTH_FT MAX_LINEAR_TRAVEL_FT].each do |name|
      expect(frontend_constant("geo.ts", name)).to eq(Pivot.const_get(name)), name.to_s
    end
  end

  it "has FieldBoundary's limits and Pivot's latitudes and longitudes in lib/geo.ts" do
    expect(frontend_constant("geo.ts", "MAX_BOUNDARY_VERTICES")).to eq(FieldBoundary::MAX_VERTICES)
    expect(frontend_constant("geo.ts", "MAX_FIELD_ACRES")).to eq(FieldBoundary::MAX_ACRES)
    expect(frontend_constant("geo.ts", "MIN_FIELD_ACRES")).to eq(FieldBoundary::MIN_ACRES)
    expect([frontend_constant("geo.ts", "MIN_LATITUDE"), frontend_constant("geo.ts", "MAX_LATITUDE")])
      .to eq([Pivot::LATITUDES.begin, Pivot::LATITUDES.end])
    expect([frontend_constant("geo.ts", "MIN_LONGITUDE"), frontend_constant("geo.ts", "MAX_LONGITUDE")])
      .to eq([Pivot::LONGITUDES.begin, Pivot::LONGITUDES.end])
  end

  it "has PlantingStatus's lead days in lib/outlook.ts" do
    expect(frontend_constant("outlook.ts", "LEAD_DAYS")).to eq(PlantingStatus::LEAD_DAYS)
  end

  it "has PlantingTasks's reading advice in lib/guidance.ts" do
    expect(frontend_constant("guidance.ts", "READING_EVERY")).to eq(PlantingTasks::READING_EVERY)
    expect(frontend_constant("guidance.ts", "FULL_COVER_PCT")).to eq(PlantingTasks::FULL_COVER_PCT)
  end

  it "has Canopy's vine kill ramp in lib/guidance.ts" do
    expect(frontend_constant("guidance.ts", "VINE_KILL_DAYS")).to eq(Canopy::VINE_KILL_DAYS)
  end

  it "has Canopy's fade after the last reading in lib/guidance.ts" do
    expect(frontend_constant("guidance.ts", "FADE_DAYS")).to eq(Canopy::FADE_DAYS)
  end
end

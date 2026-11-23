require "rails_helper"

RSpec.describe WeatherZone do
  let(:group) { create(:user).groups.first }
  let(:farm) { create(:farm, group:, name: "Hancock") }

  it "groups the operation's systems by weather cell and names each zone from them" do
    north = create(:pivot, farm:, name: "North 160")
    create(:pivot, farm:, name: "River")
    away = create(:pivot, farm:, name: "Away", latitude: 45.5, longitude: -90.1)
    zones = described_class.for_group(group)
    expect(zones.map(&:name)).to eq(["Away", "North 160 and River"])
    expect(zones.last.id).to eq(north.weather_cell_id)
    expect(zones.first.coordinates).to match(/\A45\.\d\d°N, 90\.\d\d°W\z/)
    expect(away.weather_cell_id).not_to eq(north.weather_cell_id)
  end

  it "names many systems by the first few" do
    %w[A B C D E].each { |name| create(:pivot, farm:, name:) }
    expect(described_class.for_group(group).sole.name).to eq("A, B, C and 2 more")
  end

  it "finds a cell an ended season ran on after its pivot moved, and only the group's cells" do
    pivot = create(:pivot, farm:, name: "Mover")
    field = create(:field, pivot:)
    create(:planting, field:)
    old_cell = pivot.weather_cell_id
    pivot.update_columns(weather_cell_id: create(:pivot, latitude: 45.5).weather_cell_id) # moved (the planting keeps its own)
    expect(described_class.find(group, old_cell).name).to eq("Mover")
    other = create(:pivot, latitude: 46.2, longitude: -91.0) # another group's
    expect { described_class.find(group, other.weather_cell_id) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "names an earlier season's zone from the system that season ran on, not the field's current one" do
    old = create(:pivot, farm:, name: "Old")
    field = create(:field, pivot: old)
    create(:planting, field:)
    cell = old.weather_cell_id
    now = create(:pivot, farm:, name: "Now", latitude: 45.5)
    field.update_columns(pivot_id: now.id) # the field moved to another system
    old.update_columns(weather_cell_id: create(:pivot, latitude: 46.2, longitude: -91.0).weather_cell_id) # and the old one moved
    expect(described_class.find(group, cell).name).to eq("Old")
  end
end

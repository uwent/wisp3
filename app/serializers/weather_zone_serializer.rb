# A weather zone (WeatherZone) as the pages name it, with its irrigation systems
class WeatherZoneSerializer < ApplicationSerializer
  attributes :id, :name, :coordinates
  # In feet, as stored distances are (lib/units.ts converts it for metric users)
  attribute(:elevation_ft) { |zone| zone.cell.elevation_ft }
  attribute(:pivots) do |zone|
    zone.pivots.map { |pivot| {id: pivot.id, name: pivot.name, kind_name: pivot.kind_name, farm: pivot.farm.name} }
  end

  typelize id: :number, name: :string, coordinates: :string, elevation_ft: "number | null",
    pivots: "{ id: number; name: string; kind_name: string; farm: string }[]"
end

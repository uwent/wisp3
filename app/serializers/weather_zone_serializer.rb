# A weather zone (WeatherZone) as the pages name it, with its irrigation systems
class WeatherZoneSerializer < ApplicationSerializer
  attributes :id, :name, :coordinates, :location
  # In feet, as stored distances are (lib/units.ts converts it for metric users)
  attribute(:elevation_ft) { |zone| zone.cell.elevation_ft }
  attribute(:pivots) do |zone|
    zone.pivots.map { |pivot| {id: pivot.id, name: pivot.name, kind_name: pivot.kind_name, farm: pivot.farm.name} }
  end

  # The fields on its systems, by name, for links, with the system each is on
  attribute(:fields) do |zone|
    names = zone.pivots.to_h { |pivot| [pivot.id, pivot.name] }
    zone.fields.map { |field| {id: field.id, name: field.name, pivot_id: field.pivot_id, pivot: names[field.pivot_id]} }
  end

  typelize id: :number, name: :string, coordinates: :string, location: :string, elevation_ft: "number | null",
    pivots: "{ id: number; name: string; kind_name: string; farm: string }[]",
    fields: "{ id: number; name: string; pivot_id: number; pivot: string }[]"
end

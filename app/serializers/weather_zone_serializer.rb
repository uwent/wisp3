# A weather zone (WeatherZone) as the pages name it, with its irrigation systems
class WeatherZoneSerializer < ApplicationSerializer
  attributes :id, :name, :coordinates, :location
  # In feet, as stored distances are (lib/units.ts converts it for metric users)
  attribute(:elevation_ft) { |zone| zone.cell.elevation_ft }
  attribute(:systems) do |zone|
    zone.systems.map { |system| {id: system.id, name: system.name, kind_name: system.kind_name, farm: system.farm.name} }
  end

  # The fields on its systems, by name, for links, with the system each is on
  attribute(:fields) do |zone|
    names = zone.systems.to_h { |system| [system.id, system.name] }
    zone.fields.map { |field| {id: field.id, name: field.name, system_id: field.system_id, system: names[field.system_id]} }
  end

  typelize id: :number, name: :string, coordinates: :string, location: :string, elevation_ft: "number | null",
    systems: "{ id: number; name: string; kind_name: string; farm: string }[]",
    fields: "{ id: number; name: string; system_id: number; system: string }[]"
end

# A field with its plantings (every season). field_capacity and perm_wilting_pt are the field's
# overrides (null = the soil type's); the effective_ values are what the balance uses.
class FieldSerializer < ApplicationSerializer
  attributes :id, :pivot_id, :name, :area_acres, :soil_type_id, :field_capacity, :perm_wilting_pt, :notes

  attribute :soil_type_name do |field|
    field.soil_type.name
  end

  attribute :effective_field_capacity, &:effective_field_capacity
  attribute :effective_perm_wilting_pt, &:effective_perm_wilting_pt

  many :plantings, resource: PlantingSerializer

  typelize soil_type_name: :string, effective_field_capacity: :number, effective_perm_wilting_pt: :number
end

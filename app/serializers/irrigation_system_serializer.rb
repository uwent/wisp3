class IrrigationSystemSerializer < ApplicationSerializer
  # Where the system is and what it covers (lib/geo.ts SystemShape)
  SHAPE = %i[kind latitude longitude radius_ft arc_start_deg arc_end_deg length_ft travel_ft travel_bearing_deg].freeze
  KIND_TYPE = IrrigationSystem::KINDS.map { |kind| "'#{kind}'" }.join(" | ")

  attributes :id, :farm_id, :irrigation_group_id, :name, *SHAPE, :kind_name, :equipment, :pump_capacity_gpm,
    :inches_at_100, :notes
  typelize kind: KIND_TYPE, kind_name: :string

  many :fields, resource: FieldSerializer
end

class PivotSerializer < ApplicationSerializer
  # Where the pivot is and what it covers (lib/geo.ts PivotShape)
  SHAPE = %i[kind latitude longitude radius_ft arc_start_deg arc_end_deg length_ft travel_ft travel_bearing_deg].freeze
  KIND_TYPE = Pivot::KINDS.map { |kind| "'#{kind}'" }.join(" | ")

  attributes :id, :farm_id, :pivot_group_id, :name, *SHAPE, :kind_name, :equipment, :pump_capacity_gpm, :notes
  typelize kind: KIND_TYPE, kind_name: :string

  many :fields, resource: FieldSerializer
end

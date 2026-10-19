class PivotSerializer < ApplicationSerializer
  # Where the pivot is and what it covers (lib/geo.ts PivotShape)
  SHAPE = %i[kind latitude longitude radius_ft arc_start_deg arc_end_deg length_ft travel_ft travel_bearing_deg].freeze

  attributes :id, :farm_id, :name, *SHAPE, :equipment, :pump_capacity_gpm, :notes
  typelize kind: "'center' | 'linear'"

  many :fields, resource: FieldSerializer
end

class PivotSerializer < ApplicationSerializer
  attributes :id, :farm_id, :name, :latitude, :longitude, :radius_ft, :arc_start_deg, :arc_end_deg, :equipment,
    :pump_capacity_gpm, :notes

  many :fields, resource: FieldSerializer
end

# What the field and planting pages share (PLAN.md Phase 8 G.11): the field with every planting
# (for the tabs), its pivot and farm. The field needs its plantings, soil type and pivot with its
# farm loaded.
module FieldHeaderProps
  def self.for(field)
    {
      field: FieldSerializer.new(field).to_h,
      pivot: {id: field.pivot.id, name: field.pivot.name, pump_capacity_gpm: field.pivot.pump_capacity_gpm},
      farm: {id: field.pivot.farm.id, name: field.pivot.farm.name}
    }
  end
end

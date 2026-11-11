# What the field and planting pages share (PLAN.md Phase 8 G.11): the field with every planting
# (for the tabs), its pivot, farm and field groups. The field needs its plantings, soil type, field
# groups and pivot with its farm loaded.
module FieldHeaderProps
  def self.for(field)
    {
      field: FieldSerializer.new(field).to_h,
      pivot: {id: field.pivot.id, name: field.pivot.name, pump_capacity_gpm: field.pivot.pump_capacity_gpm},
      farm: {id: field.pivot.farm.id, name: field.pivot.farm.name},
      field_groups: field.field_groups.map { |group| {id: group.id, name: group.name} }
    }
  end
end

# What the field and planting pages share (PLAN.md Phase 8 G.11): the field with every planting
# (for the tabs), its pivot and farm. The field needs its plantings, soil type and pivot with its
# farm loaded.
module FieldHeaderProps
  def self.for(field)
    {
      field: FieldSerializer.new(field).to_h,
      pivot: field.pivot.slice(:id, :name, :kind, :pump_capacity_gpm).symbolize_keys.merge(kind_name: field.pivot.kind_name),
      farm: {id: field.pivot.farm.id, name: field.pivot.farm.name}
    }
  end
end

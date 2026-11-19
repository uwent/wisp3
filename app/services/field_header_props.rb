# What the field and planting pages share (PLAN.md Phase 8 G.11): the field with every planting
# (for the tabs), its pivot and farm. The field needs its plantings, soil type and pivot with its
# farm and group loaded.
module FieldHeaderProps
  def self.for(field)
    {
      field: FieldSerializer.new(field).to_h,
      # Its rainfall setting (Q7): its irrigation group's, else its farm's
      pivot: field.pivot.slice(:id, :name, :kind, :pump_capacity_gpm).symbolize_keys.merge(kind_name: field.pivot.kind_name,
        use_model_precip: field.pivot.use_model_precip?, pivot_group: field.pivot.pivot_group&.slice(:id, :name)&.symbolize_keys),
      farm: {id: field.pivot.farm.id, name: field.pivot.farm.name}
    }
  end
end

# What the field and planting pages share: the field with every planting
# (for the tabs), its system and farm. The field needs its plantings, soil type and system with its
# farm and group loaded.
module FieldHeaderProps
  def self.for(field)
    {
      field: FieldSerializer.new(field).to_h,
      # Its rainfall setting (Q7): its irrigation group's, else its farm's
      system: field.system.slice(:id, :name, :kind, :pump_capacity_gpm).symbolize_keys.merge(kind_name: field.system.kind_name,
        use_model_precip: field.system.use_model_precip?, irrigation_group: field.system.irrigation_group&.slice(:id, :name)&.symbolize_keys),
      farm: {id: field.system.farm.id, name: field.system.farm.name}
    }
  end
end

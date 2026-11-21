# Reference data as page props, for the pages with soil and crop pickers
module ReferenceProps
  module_function

  # Lightest to heaviest
  def soil_types = SoilTypeSerializer.new(SoilType.order(:field_capacity, :perm_wilting_pt)).to_h

  # The soil type new fields start with (SoilType::DEFAULT_KEY), or nil when it isn't seeded
  def default_soil_type_id = SoilType.find_by(key: SoilType::DEFAULT_KEY)&.id

  # What the planting form picks from: crops, soils and canopy curves
  def planting_form
    {plants: PlantSerializer.new(Plant.order(:name)).to_h, soil_types:, generic_curves: GenericCurveSerializer.all}
  end
end

# The guided first-run setup (PLAN.md §13): a farm (new, or one of the group's), a pivot and its
# fields, each with this season's crop, from one form. Everything is saved or nothing is. Fields are
# optional (they can be added later in setup); rows left blank are skipped.
#
# Errors are keyed by the form's input paths ("farm.name", "pivot.latitude", "fields.1.area_acres").
class QuickSetup
  attr_reader :errors, :pivot

  def initialize(group, params, year: Date.current.year)
    @group, @params, @year = group, params, year
    @errors = {}
  end

  def save
    Pivot.transaction do
      farm = find_or_build_farm
      @pivot = farm.pivots.build(@params.fetch(:pivot, {}))
      collect("farm", farm) unless farm.persisted? || farm.valid?
      collect("pivot", @pivot) unless @pivot.valid?
      if @errors.empty?
        farm.save!
        @pivot.save!
        fields.each { |index, field_params| build_field(field_params, index) }
      end
      raise ActiveRecord::Rollback if @errors.any?
    end
    @errors.empty?
  end

  private

  # [[index, params]] for the rows with anything typed in them, keeping each row's index for errors.
  # Soil and emergence are prefilled, so a row with neither a name, an area nor a crop is blank.
  def fields
    rows = @params.fetch(:fields, {})
    rows = rows.respond_to?(:each_pair) ? rows.each_pair.to_a : rows.each_with_index.map { |row, i| [i, row] }
    rows.reject { |_, row| row.values_at(:name, :area_acres, :plant_id).all?(&:blank?) }
  end

  def find_or_build_farm
    if @params[:farm_id].present?
      @group.farms.find(@params[:farm_id])
    else
      @group.farms.build(name: @params.dig(:farm, :name))
    end
  end

  def build_field(params, index)
    field = @pivot.fields.build(params.slice(:name, :area_acres, :soil_type_id))
    return collect("fields.#{index}", field) unless field.save

    plant = Plant.find_by(id: params[:plant_id])
    return @errors["fields.#{index}.plant_id"] = ["Choose a crop"] unless plant

    planting = field.plantings.build(Planting.defaults_for(plant, @year).merge(plant:))
    planting.emergence_date = params[:emergence_date] if params[:emergence_date].present?
    collect("fields.#{index}", planting) unless planting.save
  end

  def collect(prefix, record)
    record.errors.to_hash(true).each { |attribute, messages| @errors["#{prefix}.#{attribute}"] = messages }
  end
end

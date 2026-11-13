# The guided first-run setup (PLAN.md §13, G.6): a farm (new, or one of the group's), an irrigation
# system and the fields it waters, from one form. Everything is saved or nothing is. The system and
# the fields can each be left for later (no `pivot` params: the farm alone; no rows, or blank ones:
# the system alone). Plantings aren't made here: Setup's next steps add them, one per field.
#
# Errors are keyed by the form's input paths ("farm.name", "pivot.latitude", "fields.1.area_acres").
class QuickSetup
  attr_reader :errors, :farm, :pivot

  def initialize(group, params)
    @group, @params = group, params
    @errors = {}
  end

  def save
    Pivot.transaction do
      @farm = find_or_build_farm
      collect("farm", farm) unless farm.persisted? || farm.valid?
      @pivot = farm.pivots.build(@params[:pivot]) if @params[:pivot].present?
      collect("pivot", pivot) if pivot && !pivot.valid?
      if @errors.empty?
        farm.save!
        if pivot
          pivot.save!
          fields.each { |index, field_params| build_field(field_params, index) }
        end
      end
      raise ActiveRecord::Rollback if @errors.any?
    end
    @errors.empty?
  end

  private

  # [[index, params]] for the rows with anything typed in them, keeping each row's index for errors.
  # Soil is prefilled, so a row with neither a name nor an area is blank.
  def fields
    rows = @params.fetch(:fields, {})
    rows = rows.respond_to?(:each_pair) ? rows.each_pair.to_a : rows.each_with_index.map { |row, i| [i, row] }
    rows.reject { |_, row| row.values_at(:name, :area_acres).all?(&:blank?) }
  end

  def find_or_build_farm
    if @params[:farm_id].present?
      @group.farms.find(@params[:farm_id])
    else
      @group.farms.build(name: @params.dig(:farm, :name))
    end
  end

  def build_field(params, index)
    field = pivot.fields.build(params.slice(:name, :area_acres, :soil_type_id))
    collect("fields.#{index}", field) unless field.save
  end

  def collect(prefix, record)
    record.errors.to_hash(true).each { |attribute, messages| @errors["#{prefix}.#{attribute}"] = messages }
  end
end

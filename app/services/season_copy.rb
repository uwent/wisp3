# "Copy last season": for each of a group's fields with plantings last year and none
# this year, the same crops and settings with every date a year later. Canopy readings and daily
# entries belong to the old season and aren't copied.
class SeasonCopy
  # by: the user copying, who is each copy's creator
  def initialize(group, year, by: nil)
    @group, @year, @by = group, year, by
  end

  # copied: the plantings created; failed: the copies that didn't save (check their errors)
  Result = Data.define(:copied, :failed)

  def run
    fields = @group.fields.includes(:soil_type, plantings: :plant)
    copies = Planting.transaction do
      fields.flat_map do |field|
        next [] if field.plantings.any? { |planting| planting.season_year == @year }
        field.plantings.select { |planting| planting.season_year == @year - 1 }.map { |planting| copy(planting) }
      end
    end
    Result.new(copied: copies.select(&:persisted?), failed: copies.reject(&:persisted?))
  end

  private

  def copy(planting)
    attributes = planting.attributes.slice(*%w[field_id plant_id variety max_root_zone_depth mad_frac et_method
      canopy_interpolation canopy_curve_key season_days target_ad_pct initial_moisture_pct notes partial plot_length_ft
      plot_width_ft])
    # A plot keeps its size; a whole-field planting takes the field's area as it is now. A plot
    # on its own soil keeps that too; the rest take the field's soil as it is now.
    attributes["area_acres"] = planting.area_acres if planting.partial?
    if planting.own_soil?
      attributes.merge!(planting.attributes.slice(*%w[own_soil soil_type_id field_capacity perm_wilting_pt]))
    end
    dates = %w[season_start emergence_date end_date vine_kill_date].to_h { |column| [column, planting[column]&.next_year] }
    Planting.new(attributes.merge(dates, "created_by_id" => @by&.id)).tap(&:save)
  end
end

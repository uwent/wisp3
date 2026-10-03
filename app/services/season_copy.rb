# "Copy last season" (PLAN.md §11): for each of a group's fields with plantings last year and none
# this year, the same crops and settings with every date a year later. Canopy readings and daily
# entries belong to the old season and aren't copied.
class SeasonCopy
  def initialize(group, year)
    @group, @year = group, year
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
      target_ad_pct initial_moisture_pct notes])
    dates = %w[season_start emergence_date end_date].to_h { |column| [column, planting[column].next_year] }
    Planting.new(attributes.merge(dates)).tap(&:save)
  end
end

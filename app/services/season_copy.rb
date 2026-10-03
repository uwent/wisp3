# "Copy last season" (PLAN.md §11): for each of a group's fields with plantings last year and none
# this year, the same crops and settings with every date a year later. Canopy readings and daily
# entries belong to the old season and aren't copied.
class SeasonCopy
  def initialize(group, year)
    @group, @year = group, year
  end

  # The plantings created
  def run
    fields = @group.fields.includes(:plantings)
    Planting.transaction do
      fields.flat_map do |field|
        next [] if field.plantings.any? { |planting| planting.season_year == @year }
        field.plantings.select { |planting| planting.season_year == @year - 1 }.filter_map { |planting| copy(planting) }
      end
    end
  end

  private

  def copy(planting)
    attributes = planting.attributes.slice(*%w[field_id plant_id variety max_root_zone_depth mad_frac et_method
      target_ad_pct initial_moisture_pct notes])
    dates = %w[season_start emergence_date end_date].to_h { |column| [column, planting[column].next_year] }
    copy = Planting.new(attributes.merge(dates))
    copy if copy.save
  end
end

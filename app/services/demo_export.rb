# Writes a group's farms back as DemoSeed's file (bin/rails demo:export): the demo account edited in
# the app (systems moved, outlines redrawn, names changed) becomes the seed again. Dates are written
# as month-day, so every date must be in the year exported; values that follow a default (a
# planting's root zone and MAD, a field's soil values) are left out.
class DemoExport
  SYSTEM_ATTRIBUTES = %w[name kind latitude longitude radius_ft arc_start_deg arc_end_deg length_ft travel_ft
    travel_bearing_deg pump_capacity_gpm inches_at_100 equipment notes].freeze
  FIELD_ATTRIBUTES = %w[area_acres field_capacity perm_wilting_pt notes].freeze
  PLANTING_ATTRIBUTES = %w[variety et_method target_ad_pct initial_moisture_pct max_root_zone_depth mad_frac
    canopy_interpolation canopy_curve_key season_days partial plot_length_ft plot_width_ft own_soil notes].freeze
  ENTRY_VALUES = %w[rain_in irrigation_in irrigation_pct soil_moisture_pct notes].freeze

  HEADER = <<~YAML
    # The demo farms (DemoSeed, bin/rails demo:seed). Written by bin/rails demo:export from the demo
    # account; dates are month-day in the year seeded, outlines [longitude, latitude] rings.
  YAML

  def initialize(group, year:)
    @group, @year = group, year
  end

  def to_yaml
    visitor = Psych::Visitors::YAMLTree.create
    visitor << data
    compact(visitor.tree)
    HEADER + visitor.tree.yaml(nil, line_width: -1).delete_prefix("---\n")
  end

  def data
    {"farms" => @group.farms.order(:id).includes(pivot_groups: :pivots).map do |farm|
      # Its rainfall setting only when it isn't the default, modeled rain
      {"name" => farm.name, "notes" => farm.notes, "use_model_precip" => (false unless farm.use_model_precip),
       "systems" => farm.pivots.reorder(:id).map { |pivot| system(pivot) },
       "irrigation_groups" => farm.pivot_groups.order(:id).map do |pivot_group|
         {"name" => pivot_group.name, "use_model_precip" => pivot_group.use_model_precip,
          "systems" => pivot_group.pivots.sort_by(&:id).map(&:name)}.compact
       end.presence}.compact
    end}
  end

  private

  def system(pivot)
    fields = pivot.fields.reorder(:id).to_a
    names = fields.to_h { |field| [field.id, field.name] }
    irrigation = pivot.pivot_irrigations.order(:date).map do |irrigation|
      {"date" => month_day(irrigation.date), "inches" => irrigation.inches, "run_hours" => irrigation.run_hours,
       "percent_timer" => irrigation.percent_timer, "circles" => irrigation.circles,
       "fields" => irrigation.field_ids&.map { |id| names.fetch(id) }, "notes" => irrigation.notes}.compact
    end
    values(pivot, SYSTEM_ATTRIBUTES).merge("irrigation" => irrigation.presence, "fields" => fields.map { |field| field(field) }).compact
  end

  def field(field)
    {"name" => field.name, **values(field, FIELD_ATTRIBUTES), "soil" => field.soil_type.key,
     "boundary" => field.boundary&.dig("coordinates", 0),
     "entries" => entries(field.field_entries).presence,
     "plantings" => field.plantings.reorder(:season_start, :id).map { |planting| planting(planting) }.presence}.compact
  end

  def planting(planting)
    defaults = Planting.defaults_for(planting.plant, @year).transform_keys(&:to_s)
    attributes = values(planting, PLANTING_ATTRIBUTES).reject { |key, value| defaults[key] == value }
    attributes.delete("partial") unless planting.partial?
    attributes.delete("own_soil") unless planting.own_soil?
    {"crop" => planting.plant.key, "season_start" => month_day(planting.season_start),
     "emergence" => month_day(planting.emergence_date), "end" => month_day(planting.end_date),
     "vine_kill" => planting.vine_kill_date && month_day(planting.vine_kill_date), **attributes,
     "canopy" => planting.canopy_observations.order(:date).map do |reading|
       {"date" => month_day(reading.date), **values(reading, %w[pct_cover lai])}
     end.presence,
     "cuttings" => planting.canopy_cuttings.order(:date).map { |cutting| month_day(cutting.date) }.presence,
     "entries" => entries(planting.planting_entries).presence}.compact
  end

  def entries(relation)
    relation.order(:date).map { |entry| {"date" => month_day(entry.date), **values(entry, ENTRY_VALUES)} }
  end

  # The attributes set, whole numbers written without their ".0"
  def values(record, names)
    record.attributes.slice(*names).compact.transform_values { |value| (value.is_a?(Float) && value == value.round) ? value.to_i : value }
  end

  def month_day(date)
    raise ArgumentError, "#{date} isn't in #{@year}: the demo file holds one season" unless date.year == @year
    date.strftime("%m-%d")
  end

  # Short lists and dated rows on one line each ([lng, lat], {date: …, rain_in: …}), the rest as blocks
  def compact(node)
    case node
    when Psych::Nodes::Scalar
      # Month-days read back as strings unquoted; Psych quotes some ('08-15') and not others
      node.plain, node.quoted, node.style = true, false, Psych::Nodes::Scalar::PLAIN if node.value.match?(/\A\d\d-\d\d\z/)
    when Psych::Nodes::Sequence
      node.style = Psych::Nodes::Sequence::FLOW if node.children.all?(Psych::Nodes::Scalar)
    when Psych::Nodes::Mapping
      keys = node.children.each_slice(2).map { |key, _| key.value }
      short = node.children.all? { |child| child.is_a?(Psych::Nodes::Scalar) || child.children.all?(Psych::Nodes::Scalar) }
      node.style = Psych::Nodes::Mapping::FLOW if keys.include?("date") && short
    end
    node.children&.each { |child| compact(child) }
  end
end

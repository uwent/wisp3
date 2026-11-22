# A realistic demo account for development, staging, the beta and the example farm (bin/rails
# demo:seed; PLAN.md Phase 8 G.8), built from db/demo/farms.yml: three farms on real fields seen on
# the imagery (Arlington's silt loams, mostly rainfed; Coloma's pivot-scale potatoes and processing
# vegetables on sand, outlines from a field map; Hancock Agricultural Research Station's K fields
# under a linear and R fields under a pivot). Between them they show split pivots, a linear, a
# traveler set up at two fields, a solid set over research plots (one plot with its own drip
# irrigation and readings), a location-only rainfed field, double crops, alfalfa cuttings, both ET
# methods, irrigation by system (all fields and a subset) and by field, soil
# moisture readings, rain gauges shared by irrigation groups, and outlines for every field.
#
# The file holds month-day dates, placed in the year seeded. To change the layout, edit the demo
# account in the app (move systems, redraw outlines, rename) and write it back with bin/rails
# demo:export (DemoExport), or edit the file. Rebuilds the demo group from scratch each run.
# Weather comes from Phase 3's fetch.
class DemoSeed
  GROUP_NAME = "Demo farms"
  FILE = Rails.root.join("db/demo/farms.yml")

  # The public example farm (PLAN.md G.8): the same farms in a group of their own, with no members,
  # shown as of July 20 of the season seeded
  EXAMPLE_NAME = "Example farm"
  EXAMPLE_DAY = [7, 20].freeze

  # Rebuilds the example farm (bin/rails demo:example), replacing any other
  def self.example!(year: Date.current.year, file: FILE)
    ActiveRecord::Base.transaction do
      Group.examples.destroy_all
      group = Group.create!(name: EXAMPLE_NAME, example_as_of: Date.new(year, *EXAMPLE_DAY))
      new(email: nil, year:, file:).build(group, YAML.safe_load_file(file))
      group
    end
  end

  def initialize(email:, password: nil, year: Date.current.year, file: FILE)
    @email, @password, @year, @file = email, password, year, file
  end

  def run
    user = User.find_or_initialize_by(email: @email)
    generated = (user.new_record? && @password.nil?) ? SecureRandom.base58(12) : nil
    if user.new_record?
      user.assign_attributes(first_name: "Demo", last_name: "Grower", password: @password || generated)
      user.skip_confirmation!
      user.save!
    end

    group = nil
    ActiveRecord::Base.transaction do
      user.groups.where(name: GROUP_NAME).destroy_all
      group = Group.create!(name: GROUP_NAME)
      user.memberships.create!(group:, owner: true)
      build(group, YAML.safe_load_file(@file))
    end

    {email: @email, password: generated, farms: group.farms.count, fields: group.fields.count,
     plantings: group.plantings.count}
  end

  def build(group, data)
    data.fetch("farms").each do |farm_data|
      farm = group.farms.create!(name: farm_data.fetch("name"), notes: farm_data["notes"], use_model_precip: farm_data.fetch("use_model_precip", true))
      systems = farm_data.fetch("systems").to_h { |system_data| [system_data.fetch("name").to_s, system(farm, system_data)] }
      Array(farm_data["irrigation_groups"]).each do |group_data|
        farm.pivot_groups.create!(name: group_data.fetch("name"), use_model_precip: group_data["use_model_precip"]).pivots << systems.fetch_values(*group_data.fetch("systems").map(&:to_s))
      end
    end
  end

  private

  def date(month_day) = Date.strptime("#{@year}-#{month_day}", "%Y-%m-%d")

  def system(farm, data)
    pivot = farm.pivots.create!(data.slice(*DemoExport::SYSTEM_ATTRIBUTES))
    fields = data.fetch("fields").to_h { |field_data| [field_data.fetch("name").to_s, field(pivot, field_data)] }
    # A system's irrigation (D15: stored per field) goes on each field it lists, else each on it that
    # day, and their plots; a field's own amount that day (its entries) stays
    Array(data["irrigation"]).each do |irrigation|
      day = date(irrigation.fetch("date"))
      watered = irrigation["fields"] ? fields.fetch_values(*irrigation["fields"].map(&:to_s)) : pivot.fields_on(day)
      watered.each do |field|
        next if field.field_entries.find_by(date: day)&.irrigation_in
        field.record_entry(day, irrigation.slice("notes").merge(irrigation_in: irrigation.fetch("inches")))
      end
    end
    pivot
  end

  def field(pivot, data)
    field = pivot.fields.create!(data.slice(*DemoExport::FIELD_ATTRIBUTES)
      .merge(name: data.fetch("name").to_s, soil_type: SoilType.find_by!(key: data.fetch("soil")),
        boundary: data["boundary"] && {"type" => "Polygon", "coordinates" => [data["boundary"]]}))
    Array(data["entries"]).each { |entry| field.field_entries.create!(entry(entry)) }
    Array(data["plantings"]).each { |planting_data| planting(field, planting_data) }
    field
  end

  def planting(field, data)
    crop = Plant.find_by!(key: data.fetch("crop"))
    planting = field.plantings.create!(Planting.defaults_for(crop, @year).merge(
      data.slice(*DemoExport::PLANTING_ATTRIBUTES), plant: crop, season_start: date(data.fetch("season_start")),
      emergence_date: date(data.fetch("emergence")), end_date: date(data.fetch("end")),
      vine_kill_date: data["vine_kill"] && date(data["vine_kill"])
    ))
    Array(data["canopy"]).each { |reading| planting.canopy_observations.create!(entry(reading)) }
    Array(data["cuttings"]).each { |cutting| planting.canopy_cuttings.create!(date: date(cutting)) }
    Array(data["entries"]).each { |entry| planting.planting_entries.create!(entry(entry)) }
    planting
  end

  def entry(data) = data.merge("date" => date(data.fetch("date")))
end

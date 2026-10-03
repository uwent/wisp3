# A realistic demo account for development, staging and the beta (bin/rails demo:seed): several
# farms in the Central Sands, single- and multi-field pivots (one with seven fields), both ET
# methods, canopy readings, irrigation by field, by pivot (inches and run hours, all fields and a
# subset), a soil moisture reading, and a field group sharing a rain gauge. Rebuilds the demo
# group from scratch each run. Weather comes from Phase 3's fetch.
class DemoSeed
  GROUP_NAME = "Demo farms"

  def initialize(email:, password: nil, year: Date.current.year)
    @email, @password, @year = email, password, year
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
      user.memberships.create!(group:, admin: true)
      build(group)
    end

    {email: @email, password: generated, farms: group.farms.count, fields: group.fields.count,
     plantings: group.plantings.count}
  end

  private

  def date(month, day) = Date.new(@year, month, day)
  def plant(key) = Plant.find_by!(key:)
  def soil(key) = SoilType.find_by!(key:)

  def build(group)
    hancock = group.farms.create!(name: "Hancock Sands")
    plover = group.farms.create!(name: "Plover River")
    coloma = group.farms.create!(name: "Coloma Vegetables")

    # Two crops split under one pivot, irrigated together
    north = hancock.pivots.create!(name: "North 160", latitude: 44.1335, longitude: -89.5213, radius_ft: 1300,
      pump_capacity_gpm: 900, equipment: "Valley 8000, end gun")
    potato = field(north, "North potatoes", 70, "sand")
    corn = field(north, "North corn", 55, "sand")
    planting(potato, "potato", variety: "Russet Burbank", emergence: date(5, 20), end_date: date(9, 15), target: 40)
    planting(corn, "field_corn", et_method: "lai", emergence: date(5, 12), end_date: date(9, 30))
    pivot_irrigations(north, [[6, 18, 0.8], [6, 29, 0.75], [7, 8, 0.9], [7, 21, 0.85], [8, 3, 0.8]])
    north.pivot_irrigations.create!(date: date(7, 14), run_hours: 20) # inches from pump capacity
    north.pivot_irrigations.create!(date: date(8, 12), inches: 0.6, field_ids: [potato.id]) # potatoes only

    # A single-field pivot with entered irrigation and a soil moisture reading
    south = hancock.pivots.create!(name: "South 80", latitude: 44.1129, longitude: -89.5371, radius_ft: 950,
      arc_start_deg: 30, arc_end_deg: 300, pump_capacity_gpm: 600)
    beans = field(south, "South snap beans", 48, "sandy_loam")
    planting(beans, "snap_bean", emergence: date(6, 5), end_date: date(8, 25), target: 50)
    [[6, 25, 0.6], [7, 6, 0.7], [7, 18, 0.7], [8, 1, 0.65]].each do |month, day, inches|
      beans.field_entries.create!(date: date(month, day), irrigation_in: inches)
    end
    beans.field_entries.create!(date: date(7, 10), soil_moisture_pct: 11.5, notes: "Probe reading, 12 in")

    # Seven fields on one pivot (the most in legacy production), a soybean double crop after peas
    river = plover.pivots.create!(name: "River pivot", latitude: 44.4512, longitude: -89.5468, radius_ft: 1450,
      pump_capacity_gpm: 1100)
    sevens = %w[A B C D E F G].map.with_index do |letter, i|
      field(river, "River #{letter}", 18 + i * 2, i.even? ? "sand" : "sandy_loam")
    end
    crops = %w[potato potato sweet_corn soybean field_corn carrot onion]
    sevens.zip(crops).each_with_index do |(f, crop), i|
      planting(f, crop, emergence: date(5, 10 + i * 3), end_date: date(9, 10 + i))
    end
    peas = field(river, "River H peas then soybeans", 22, "sandy_loam")
    planting(peas, "shell_peas", season_start: date(4, 1), emergence: date(4, 25), end_date: date(6, 30))
    planting(peas, "soybean", season_start: date(7, 1), emergence: date(7, 8), end_date: date(10, 5))
    pivot_irrigations(river, [[6, 22, 0.7], [7, 5, 0.8], [7, 19, 0.8], [8, 2, 0.75]])

    # Vegetables sharing a rain gauge (field group)
    veg = coloma.pivots.create!(name: "Home pivot", latitude: 44.0337, longitude: -89.5208, radius_ft: 1100,
      pump_capacity_gpm: 750)
    cabbage = field(veg, "Cabbage", 30, "loam")
    pepper = field(veg, "Peppers", 25, "loam")
    planting(cabbage, "cabbage", emergence: date(5, 28), end_date: date(9, 5))
    planting(pepper, "pepper", emergence: date(6, 2), end_date: date(9, 20))
    gauge = group.field_groups.create!(name: "Home rain gauge")
    gauge.fields << [cabbage, pepper]
    [[6, 12, 0.9], [7, 3, 1.4], [7, 27, 0.35], [8, 15, 0.6]].each do |month, day, rain|
      gauge.field_group_entries.create!(date: date(month, day), rain_in: rain)
    end
    gauge.field_group_entries.create!(date: date(7, 15), rain_in: 0.0, notes: "Storm missed us")
  end

  def field(pivot, name, acres, soil_key)
    pivot.fields.create!(name:, area_acres: acres, soil_type: soil(soil_key))
  end

  # Percent-cover plantings get readings that rise to full cover; LAI ones use the plant's curve
  def planting(field, plant_key, emergence:, end_date:, season_start: date(4, 1), et_method: "pct_cover", variety: nil,
    target: nil)
    crop = plant(plant_key)
    planting = field.plantings.create!(Planting.defaults_for(crop, @year).merge(
      plant: crop, season_start:, emergence_date: emergence, end_date:, et_method:, variety:, target_ad_pct: target
    ))
    if et_method == "pct_cover"
      [[14, 10], [28, 35], [42, 70], [56, 90]].each do |days, cover|
        reading = emergence + days
        planting.canopy_observations.create!(date: reading, pct_cover: cover) if reading <= end_date
      end
    end
    planting
  end

  def pivot_irrigations(pivot, events)
    events.each { |month, day, inches| pivot.pivot_irrigations.create!(date: date(month, day), inches:) }
  end
end

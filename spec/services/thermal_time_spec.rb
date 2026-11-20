require "rails_helper"

# Canopy curves in growing degree days (PLAN.md §9 C23): the temperatures behind them
# (CellTemperatures, ThermalTime), the curves (CanopyCurve), a planting's canopy (Canopy.for) and
# pages running many plantings (FieldStatuses).
RSpec.describe ThermalTime do
  let(:cell) { WeatherCell.for(44.12, -89.53) }
  let(:emergence) { Date.new(2026, 5, 15) }

  # The cell's normals: the same high and low every day of the year
  def give_normals(cell, tmax_f, tmin_f)
    now = Time.current
    WeatherNormal.insert_all!((1..366).map do |day_of_year|
      {weather_cell_id: cell.id, day_of_year:, tmax_f:, tmin_f:, first_year: 2006, last_year: 2025, model: "era5_seamless",
       fetched_at: now, created_at: now, updated_at: now}
    end)
  end

  def store_day(cell, date, tmax_f, tmin_f)
    cell.weather_days.create!(date:, tmax_f:, tmin_f:, et0_in: 0.2, precip_in: 0, model: "ncep_nbm_conus", hours: 24, fetched_at: Time.current)
  end

  # Temperatures that give `gdd` °C days a day above base_c (high and low alike, under the upper)
  def steady(gdd, base_c) = ((base_c + gdd) * 9 / 5.0 + 32).then { |f| [f, f] }

  describe "Weather::DegreeDays.aquacrop (method 3)" do
    it "holds the max between base and upper, the min only under the upper, and the mean at least the base" do
      # Potato (base 2 °C, upper 26 °C). A worked day: high 86 °F (30 °C → 26), low 50 °F (10 °C):
      # (26 + 10) / 2 − 2 = 16 °C days
      expect(Weather::DegreeDays.aquacrop(86, 50, base_c: 2, upper_c: 26)).to be_within(1e-9).of(16.0)
      # A cold night counts: high 59 °F (15 °C), low 23 °F (−5 °C): (15 − 5) / 2 − 2 = 3 (method 2 would give 6.5)
      expect(Weather::DegreeDays.aquacrop(59, 23, base_c: 2, upper_c: 26)).to be_within(1e-9).of(3.0)
      # A cold day: high 41 °F (5 °C), low 14 °F (−10 °C): mean −2.5, so 0
      expect(Weather::DegreeDays.aquacrop(41, 14, base_c: 2, upper_c: 26)).to eq(0.0)
      # A hot night is held at the upper too: 104 °F / 95 °F (40 / 35 °C) → (30 + 30) / 2 − 8 = 22 for maize
      expect(Weather::DegreeDays.aquacrop(104, 95, base_c: 8, upper_c: 30)).to be_within(1e-9).of(22.0)
      expect(Weather::DegreeDays.aquacrop(nil, 50, base_c: 2, upper_c: 26)).to be_nil
    end
  end

  describe CellTemperatures do
    it "takes stored days, then the latest forecast, then the normals, and has no thermal time without normals" do
      store_day(cell, emergence, 80.0, 60.0)
      cell.weather_forecasts.create!(kind: "deterministic", issued_at: 1.hour.ago, model: "best_match",
        payload: {days: [{date: emergence.iso8601, tmax_f: 99.0, tmin_f: 99.0}, {date: (emergence + 1).iso8601, tmax_f: 70.0, tmin_f: 50.0}]})
      dates = emergence - 5..emergence + 5
      temps = CellTemperatures.for(cell.id, dates)
      expect(temps.on(emergence)).to eq([80.0, 60.0]) # stored wins over the forecast
      expect(temps.on(emergence + 1)).to eq([70.0, 50.0])
      expect(temps.on(emergence + 2)).to be_nil
      expect(temps).not_to be_normals
      expect(temps.thermal_time(base_c: 2, upper_c: 26)).to be_nil

      give_normals(cell, 68.0, 50.0)
      temps = CellTemperatures.for(cell.id, dates)
      expect(temps.on(emergence + 2)).to eq([68.0, 50.0])
      expect(temps.on(Date.new(2030, 1, 1))).to eq([68.0, 50.0]) # any day, after the forecast or missing
    end

    it "loads any number of cells in three queries" do
      cells = [cell, WeatherCell.for(43.0, -89.4), WeatherCell.for(45.0, -90.0)]
      cells.each { |c| give_normals(c, 70.0, 50.0) }
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        CellTemperatures.by_cell(cells.map(&:id), emergence..emergence + 30)
      end
      expect(count).to eq(3)
    end
  end

  it "sums degree days from one date up to another, either way, at constant time" do
    give_normals(cell, *steady(10, 2))
    store_day(cell, emergence, 86.0, 50.0) # 16 °C days for potato
    clock = CellTemperatures.for(cell.id, emergence..emergence + 30).thermal_time(base_c: 2, upper_c: 26)
    expect(clock.on(emergence)).to be_within(1e-9).of(16.0)
    expect(clock.between(emergence, emergence)).to eq(0.0)
    expect(clock.between(emergence, emergence + 3)).to be_within(1e-9).of(36.0) # 16 + 10 + 10
    expect(clock.between(emergence - 2, emergence)).to be_within(1e-9).of(20.0)
    expect(clock.between(emergence + 3, emergence)).to be_within(1e-9).of(-36.0)
  end

  describe CanopyCurve do
    let(:potato) { CanopyCurve.for("potato") }

    def clock_at(gdd, base_c, upper_c = 26)
      CellTemperatures.new({}, (1..366).to_h { |day| [day, steady(gdd, base_c)] }).thermal_time(base_c:, upper_c:)
    end

    def day_reaching(curve, pct, **) = (0..200).find { |day| curve.cover(emergence, emergence + day, **) >= pct }

    it "has thermal parameters for every curve, from AquaCrop's temperatures where it has a crop file" do
      (CanopyCurve.all.values + CanopyCurve.generic.values).each do |curve|
        expect(curve.thermal).to be_present, curve.key
        expect(curve.thermal.cgc).to be_between(0.002, 0.03), curve.key
        expect(curve.thermal.basis).to be_present
      end
      expect(potato.thermal).to have_attributes(base_c: 2, upper_c: 26, emergence: "05-15")
      expect(CanopyCurve.for("field_corn").thermal).to have_attributes(base_c: 8, upper_c: 30)
    end

    it "grows by degree days: at the degree days a day the calendar curve's rate implies, it is the calendar curve" do
      per_day = potato.cgc / potato.thermal.cgc # about 14 °C days a day
      clock = clock_at(per_day, 2)
      (0..60).step(5).each do |day|
        expect(potato.cover(emergence, emergence + day, clock:)).to be_within(1e-6).of(potato.cover(emergence, emergence + day))
      end
    end

    it "runs ahead in a warm spring and behind in a cool one, and by calendar days without a clock" do
      calendar = day_reaching(potato, 80)
      expect(calendar).to eq(31)
      expect(day_reaching(potato, 80, clock: clock_at(20, 2))).to be < calendar
      expect(day_reaching(potato, 80, clock: clock_at(8, 2))).to be > calendar + 15
      # A fit's shift moves the day the degree days start from
      clock = clock_at(14, 2)
      expect(day_reaching(potato, 80, clock:, shift: 5)).to eq(day_reaching(potato, 80, clock:) + 5)
    end

    it "keeps potato's July 25 decline in a cool season, starting it when the canopy is full if that's later" do
      # 6 °C days a day: full (98% of 92%) after about 565 °C days, on Aug 18, so the decline starts then
      cool = clock_at(6, 2)
      covers = (Date.new(2026, 7, 20)..Date.new(2026, 10, 15)).to_h { |date| [date, potato.cover(emergence, date, clock: cool)] }
      peak = covers.max_by(&:last)
      expect(peak.first).to be_between(Date.new(2026, 8, 17), Date.new(2026, 8, 25)) # the S-curve leaves full cover slowly
      expect(peak.last).to be_within(2).of(92)
      expect(covers[Date.new(2026, 7, 26)]).to be > covers[Date.new(2026, 7, 25)] # still growing after July 25
      expect(covers[Date.new(2026, 10, 1)]).to eq(50.0)
      warm = clock_at(20, 2)
      expect(potato.cover(emergence, Date.new(2026, 8, 15), clock: warm)).to be_within(0.01).of(potato.cover(emergence, Date.new(2026, 8, 15)))
    end

    it "starts an AquaCrop decline at its degree days" do
      corn = CanopyCurve.for("field_corn")
      clock = clock_at(10, 8, 30)
      start = (corn.thermal.decline_start / 10.0).ceil # days
      expect(corn.cover(emergence, emergence + start - 1, clock:)).to be_within(0.01).of(96)
      expect(corn.cover(emergence, emergence + start + 30, clock:)).to be < 90
    end

    it "starts the late season (C22) where the curve in degree days declines" do
      corn = CanopyCurve.for("field_corn")
      clock = clock_at(10, 8, 30)
      late = corn.decline_start(emergence, clock:)
      expect(corn.cover(emergence, late + 1, clock:)).to be < corn.cover(emergence, late, clock:)
      expect(corn.cover(emergence, late, clock:)).to be_within(0.01).of(96)
      expect(potato.decline_start(emergence, clock: clock_at(6, 2))).to be_between(Date.new(2026, 8, 17), Date.new(2026, 8, 25))
      expect(potato.decline_start(emergence, clock: clock_at(20, 2))).to eq(Date.new(2026, 7, 25))
    end
  end

  describe "a planting's canopy" do
    let(:pivot) { create(:pivot, latitude: 44.12, longitude: -89.53) }
    let(:planting) { create(:planting, field: create(:field, pivot:), plant: create(:plant, key: "potato")) }

    it "runs in degree days at a cell with normals, and by calendar days until it has them" do
      calendar = Canopy.for(planting)
      expect(calendar).not_to be_thermal
      give_normals(pivot.weather_cell, *steady(8, 2)) # a cold year: about half the curve's typical warmth
      thermal = Canopy.for(planting.reload)
      expect(thermal).to be_thermal
      expect(thermal.on(emergence + 31)).to be < calendar.on(emergence + 31) - 30
      expect(Canopy.for(planting, temperatures: CellTemperatures.new({}, nil))).not_to be_thermal

      lai = create(:planting, field: create(:field, pivot:), plant: create(:plant, key: "field_corn", canopy_model: "field_corn"),
        et_method: "lai")
      expect(Canopy.for(lai)).not_to be_thermal # LAI curves stay in calendar days
    end

    it "refits its readings when the weather behind them changes" do
      give_normals(pivot.weather_cell, *steady(14, 2))
      day = store_day(pivot.weather_cell, emergence + 3, 70.0, 50.0)
      create(:canopy_observation, planting:, date: emergence + 20, pct_cover: 30.0)
      create(:canopy_observation, planting:, date: emergence + 27, pct_cover: 60.0)
      allow(CanopyFit).to receive(:run).and_call_original
      2.times { Canopy.for(planting.reload) }
      expect(CanopyFit).to have_received(:run).once
      day.update!(tmax_f: 90.0)
      Canopy.for(planting.reload)
      expect(CanopyFit).to have_received(:run).twice
    end

    it "preloads every planting's temperatures on pages running many (FieldStatuses), in the same queries for one or several cells" do
      plant = create(:plant, key: "potato")
      queries = lambda do |n|
        fields = (1...n).map { |i| create(:field, pivot: create(:pivot, latitude: 44.12 + i, longitude: -89.53)) }
        fields << create(:field, pivot:)
        fields.each do |field|
          give_normals(field.pivot.weather_cell, *steady(14, 2)) unless field.pivot.weather_cell.normals?
          create(:planting, field:, plant:)
        end
        count = 0
        counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
        statuses = ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          scope = Field.where(id: fields.map(&:id)).includes(:soil_type, pivot: :weather_cell,
            plantings: [:plant, :canopy_observations, :canopy_cuttings, :soil_type])
          FieldStatuses.for(scope.to_a, today: Date.new(2026, 7, 1)).values.flatten.each { |status| status.canopy.on(Date.new(2026, 6, 15)) }
        end
        [count, statuses]
      end
      one, = queries.call(1)
      Planting.delete_all
      several, statuses = queries.call(3)
      expect(several).to eq(one)
      expect(statuses.map { |status| status.canopy.thermal? }).to all(be(true))
    end
  end
end

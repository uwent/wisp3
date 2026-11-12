require "rails_helper"

RSpec.describe "Field status and daily entry", type: :request do
  let(:user) { create(:user) }
  let(:group) { user.groups.first }
  let(:farm) { create(:farm, group:) }
  let(:pivot) { create(:pivot, farm:, pump_capacity_gpm: 900) }
  let(:field) { create(:field, pivot:, name: "North potatoes", area_acres: 60) }
  let!(:planting) do
    create(:planting, field:, season_start: Date.new(2026, 7, 1), emergence_date: Date.new(2026, 7, 1),
      end_date: Date.new(2026, 9, 30))
  end

  before do
    sign_in user
    (Date.new(2026, 7, 1)..Date.new(2026, 7, 19)).each do |date|
      pivot.weather_cell.weather_days.create!(date:, et0_in: 0.2, precip_in: (date.day == 5) ? 0.4 : 0.0, tmax_f: 85,
        tmin_f: 60, model: "ncep_nbm_conus", hours: 24, fetched_at: Time.current)
    end
  end

  around { |example| travel_to(Time.zone.local(2026, 7, 20, 9)) { example.run } }

  describe "the field page" do
    it "shows the season's balance, summary, and its zone's week ahead (G.12)" do
      pivot.weather_cell.weather_forecasts.create!(issued_at: 1.hour.ago, model: "ncep_nbm_conus",
        payload: {days: [{date: "2026-07-20", tmax_f: 90, tmin_f: 70}, {date: "2026-07-21", tmax_f: 88, tmin_f: 66}]})

      get planting_path(planting)
      expect_inertia.to render_component("Plantings/Show")
      props = inertia.props
      expect(props[:planting][:id]).to eq(planting.id)
      expect(props[:days].size).to eq(20) # Jul 1 through today
      expect(props[:days][4]).to include(date: "2026-07-05", rain: 0.4, rain_source: "model", et0: 0.2)
      expect(props[:summary]).to include(phase: "active", date: "2026-07-20", ad_max: 1.2) # 0.5 × (0.15 − 0.05) × 24 in
      expect(props[:summary][:totals]).to include(rain: 0.4)
      expect(props).not_to have_key(:weather)
      expect(props[:weather_zone]).to eq({"id" => pivot.weather_cell_id, "name" => pivot.name})
      expect(props[:forecast].map { |day| [day[:date], day[:tmax_f]] }).to eq([["2026-07-20", 90], ["2026-07-21", 88]])
    end

    it "gives the crop's canopy curve each day, and flags readings that run ahead of it (Phase 6.7)" do
      planting.update!(plant: create(:plant, key: "potato"))
      get planting_path(planting)
      expect(inertia.props[:planting]).to include(canopy_curve: true, effective_canopy_interpolation: "curve")
      day = inertia.props[:days].find { |d| d[:date] == "2026-07-15" }
      expect(day[:canopy_curve]).to be_within(0.01).of(CanopyCurve.for("potato").cover(planting.emergence_date, Date.new(2026, 7, 15)))
      expect(day[:canopy]).to eq(day[:canopy_curve]) # no readings: the curve
      expect(inertia.props[:summary][:tasks].map { |task| task[:kind] }).to eq(%w[soil_moisture canopy])

      # 30% and 50% cover are reached on days 15 and 24 of the curve; read 9 days early
      CanopyObservation.record(planting, Date.new(2026, 7, 7), 30)
      CanopyObservation.record(planting, Date.new(2026, 7, 16), 50)
      get planting_path(planting)
      check = inertia.props[:summary][:tasks].last
      expect(check).to include(kind: "canopy_check", due: true, todo: match(/days ahead of the typical potato curve/))
    end

    it "sets the field's rainfall setting, and clears it to follow the operation's (Q7)" do
      patch field_path(field), params: {field: {use_model_precip: "false"}}, headers: {"Referer" => field_url(field)}
      expect(response).to redirect_to(field_url(field))
      expect(field.reload.use_model_precip).to be(false)

      get planting_path(planting)
      expect(inertia.props[:field][:use_model_precip]).to be(false)
      expect(inertia.props[:summary][:use_model_precip]).to be(false)
      expect(inertia.props[:days][4]).to include(rain: 0.0, rain_source: "none", rain_model: 0.4)
      expect(inertia.props[:summary][:totals]).to include(rain: 0.0, rain_model: 0.4)

      patch field_path(field), params: {field: {use_model_precip: ""}}
      expect(field.reload.use_model_precip).to be_nil
    end

    it "shows a pivot's irrigation as from the pivot, and the pivot amount under a field's override" do
      pivot.pivot_irrigations.create!(date: Date.new(2026, 7, 10), inches: 0.8)
      field.field_entries.create!(date: Date.new(2026, 7, 10), irrigation_in: 0.5)
      pivot.pivot_irrigations.create!(date: Date.new(2026, 7, 12), run_hours: 10)

      get planting_path(planting)
      days = inertia.props[:days].index_by { |day| day[:date] }
      expect(days["2026-07-10"]).to include(irrigation: 0.5, irrigation_source: "entered", pivot_inches: 0.8)
      expect(days["2026-07-12"]).to include(irrigation_source: "pivot")
      expect(days["2026-07-12"][:irrigation]).to be_within(0.001).of(900 * 10 * 60 / (27_154.0 * 60))
    end

    it "queues a weather update for the field's cell, and for the dashboard's" do
      expect { get field_path(field) }.to have_enqueued_job(WeatherUpdateJob).with(pivot.weather_cell_id, quiet: false)
      Rails.cache.clear
      expect { get root_path }.to have_enqueued_job(WeatherUpdateJob).with(pivot.weather_cell_id, quiet: false)
    end

    it "says while the pivot's weather is updating, so the pages reload until it lands" do
      get root_path
      expect(inertia.props[:farms].sole[:pivots].sole).to include(weather_updating: true)
      get planting_path(planting)
      expect(inertia.props[:weather_updating]).to be(true)

      Rails.cache.delete(WeatherUpdateJob.updating_key(pivot.weather_cell_id)) # the job has run
      get root_path
      expect(inertia.props[:farms].sole[:pivots].sole).to include(weather_updating: false)
      get planting_path(planting)
      expect(inertia.props[:weather_updating]).to be(false)
    end

    it "picks another season's planting" do
      older = create(:planting, field:, season_start: Date.new(2025, 4, 1), emergence_date: Date.new(2025, 5, 1),
        end_date: Date.new(2025, 9, 1))
      get planting_path(older)
      expect(inertia.props[:summary]).to include(phase: "ended", date: "2025-09-01")

      # Links from before plantings had their own pages
      get field_path(field, planting_id: older.id, as_of: "2025-07-01")
      expect(response).to redirect_to(planting_path(older, as_of: "2025-07-01"))
    end

    it "shows an LAI planting's readings and field corn's LAI curve" do
      # Emerged Jun 1, so the curve is well above its 0.05 floor by the reading (day 39)
      planting.update!(plant: create(:plant, :field_corn), et_method: "lai", emergence_date: Date.new(2026, 6, 1))
      CanopyObservation.record(planting, Date.new(2026, 7, 10), 1.5)
      get planting_path(planting)
      day = inertia.props[:days].find { |d| d[:date] == "2026-07-10" }
      expect(day).to include(canopy_entered: 1.5, canopy: 1.5)
      expect(day[:canopy_curve]).to be_within(1e-4).of(CanopyModel.lai("field_corn", 39))
    end

    it "gives an upcoming planting's summary without today's balance or a projection" do
      planting.update!(season_start: Date.new(2026, 8, 1), emergence_date: Date.new(2026, 8, 1))
      get planting_path(planting)
      expect(inertia.props[:summary]).to include(phase: "upcoming", status: nil, date: nil, ad: nil, pct_moisture: nil,
        crossing: nil, projection: [], tasks: [])
      expect(inertia.props[:days]).to eq([])
    end

    it "gives the target, and for a field on entered rain the no-rain case beside the forecast's, without an ensemble" do
      planting.update!(target_ad_pct: 40)
      planting.canopy_observations.create!(date: Date.new(2026, 7, 1), pct_cover: 80) # adjusted ET = et0
      field.update!(use_model_precip: false)
      pivot.weather_cell.weather_forecasts.create!(issued_at: 1.hour.ago, model: "ncep_nbm_conus",
        payload: {days: (Date.new(2026, 7, 20)..Date.new(2026, 7, 22)).map { |d| {date: d.iso8601, et0_in: 0.2, precip_in: 0.5} }})

      get planting_path(planting)
      summary = inertia.props[:summary]
      expect(summary).to include(target_in: 0.48, threshold: 0.48, use_model_precip: false, ensemble_size: 0)
      # At the wilting point today (-1.2): the forecast's 0.5 in of rain a day lifts it, the no-rain case doesn't
      expect(summary[:projection].map { |day| day.slice(:date, :ad, :dry_ad, :p50, :chance) }).to eq([
        {"date" => "2026-07-21", "ad" => -0.9, "dry_ad" => -1.2, "p50" => nil, "chance" => nil},
        {"date" => "2026-07-22", "ad" => -0.6, "dry_ad" => -1.2, "p50" => nil, "chance" => nil}
      ])
      expect(summary[:dry_crossing]).to include(date: "2026-07-20", days: 0)
    end

    it "handles a field with no planting" do
      bare = create(:field, pivot:)
      get field_path(bare)
      expect_inertia.to render_component("Fields/Show")
      expect(inertia.props).to include(plantings: [], year: 2026)
      # The field's own rain from Apr 1, which nothing grows on yet
      expect(inertia.props[:days].first[:date]).to eq("2026-07-20")
      expect(inertia.props[:days].last[:date]).to eq("2026-04-01")
    end
  end

  describe "the projection" do
    # Today and 15 days ahead at 0.2 in/day of ET, and an ensemble of a dry member and a wet one
    before do
      dates = Date.new(2026, 7, 20)..Date.new(2026, 8, 4)
      cell = pivot.weather_cell
      cell.weather_forecasts.create!(issued_at: 1.hour.ago, model: "ncep_nbm_conus",
        payload: {days: dates.map { |date| {date: date.iso8601, et0_in: 0.2, precip_in: 0.0} }})
      cell.weather_forecasts.create!(kind: "ensemble", issued_at: 1.hour.ago, model: "gfs_seamless",
        payload: {dates: dates.map(&:iso8601), members: [
          {et0_in: [0.2] * 16, precip_in: [0.0] * 16}, {et0_in: [0.2] * 16, precip_in: [0.0, 1.0] + [0.0] * 14}
        ]})
    end

    it "runs the balance through the forecast, with the ensemble's range and when to irrigate" do
      get planting_path(planting)
      props = inertia.props
      expect(props[:days].last).to include(date: "2026-07-20", et0_source: "forecast", rain_source: "forecast")
      expect(props[:forecast_days].map { |day| day[:date] }).to eq((Date.new(2026, 7, 21)..Date.new(2026, 8, 4)).map(&:iso8601))
      summary = props[:summary]
      expect(summary[:ensemble_size]).to eq(2)
      expect(summary[:projection].size).to eq(15)
      expect(summary[:projection].first).to include(date: "2026-07-21", chance: 0.0)
      expect(summary[:projection].first[:p90]).to be > summary[:projection].first[:p10]
      expect(summary).to include(crossing: nil) # no canopy readings: bare soil barely uses water
      expect(summary[:threshold]).to eq(0.0)
    end

    it "takes planned irrigation on future days, but not rain or readings" do
      patch field_day_path(field, "2026-07-25"), params: {day: {irrigation_in: 1.0}, planting_id: planting.id}
      expect(field.field_entries.sole).to have_attributes(date: Date.new(2026, 7, 25), irrigation_in: 1.0)
      get planting_path(planting)
      expect(inertia.props[:forecast_days].find { |day| day[:date] == "2026-07-25" })
        .to include(irrigation: 1.0, irrigation_source: "entered")

      patch field_day_path(field, "2026-07-26"), params: {day: {rain_in: 0.5}, planting_id: planting.id},
        headers: {"HTTP_REFERER" => field_path(field)}
      follow_redirect!
      expect(inertia.props[:errors]).to include("rain_in")
      expect(field.field_entries.count).to eq(1)
    end

    it "gives each dashboard card the projection" do
      get root_path
      summary = inertia.props[:farms].sole[:pivots].sole[:fields].sole[:plantings].sole
      expect(summary[:projection].size).to eq(15)
      expect(summary[:ensemble_size]).to eq(2)
    end
  end

  describe "time travel (Phase 8 F)" do
    before do
      # An ensemble that would give the projection a band today
      dates = Date.new(2026, 7, 20)..Date.new(2026, 8, 4)
      pivot.weather_cell.weather_forecasts.create!(kind: "ensemble", issued_at: 1.hour.ago, model: "gfs_seamless",
        payload: {dates: dates.map(&:iso8601), members: [{et0_in: [0.2] * 16, precip_in: [0.0] * 16}] * 2})
    end

    it "shows the season as of an earlier day, projecting it on the weather that followed" do
      expect { get planting_path(planting, as_of: "2026-07-10") }.not_to have_enqueued_job(WeatherUpdateJob)
      props = inertia.props
      expect(props).to include(as_of: "2026-07-10", weather_updating: false,
        travel_dates: {"from" => "2026-07-01", "to" => "2026-07-19"})
      expect(props[:days].last[:date]).to eq("2026-07-10")
      expect(props[:summary]).to include(phase: "active", date: "2026-07-10", projection_source: "observed",
        ensemble_size: 0)
      # The rest of the stored weather, Jul 11–19, and nothing in the forecast's place
      expect(props[:forecast_days].map { |day| day[:date] }).to eq((Date.new(2026, 7, 11)..Date.new(2026, 7, 19)).map(&:iso8601))
      expect(props[:forecast_days].map { |day| day[:rain_source] }.uniq).to eq(["model"])
      expect(props[:summary][:projection].map { |day| day[:p50] }.uniq).to eq([nil])
      expect(props[:forecast]).to eq([]) # the zone's link only
      expect(props[:weather_zone]).to include("id" => pivot.weather_cell_id)

      get planting_path(planting)
      expect(inertia.props).to include(as_of: nil)
      expect(inertia.props[:summary]).to include(date: "2026-07-20", projection_source: "forecast")
    end

    it "ends the season at the day, then shows what was entered for the days that followed, but not canopy readings" do
      planting.update!(plant: create(:plant, key: "potato"))
      field.field_entries.create!(date: Date.new(2026, 7, 8), irrigation_in: 0.5, notes: "before")
      field.field_entries.create!(date: Date.new(2026, 7, 12), irrigation_in: 1.0, notes: "after")
      pivot.pivot_irrigations.create!(date: Date.new(2026, 7, 14), inches: 0.8)
      field.field_entries.create!(date: Date.new(2026, 7, 13), rain_in: 2.0)
      CanopyObservation.record(planting, Date.new(2026, 7, 6), 20)
      CanopyObservation.record(planting, Date.new(2026, 7, 15), 90)

      get planting_path(planting, as_of: "2026-07-10")
      days = (inertia.props[:days] + inertia.props[:forecast_days]).index_by { |day| day[:date] }
      expect(days["2026-07-08"]).to include(irrigation: 0.5, notes: "before")
      expect(inertia.props[:days].last[:date]).to eq("2026-07-10")
      expect(days["2026-07-12"]).to include(irrigation: 1.0, irrigation_source: "entered", notes: "after")
      expect(days["2026-07-13"]).to include(rain: 2.0, rain_source: "entered")
      expect(days["2026-07-14"]).to include(irrigation: 0.8, irrigation_source: "pivot")
      expect(days["2026-07-06"][:canopy_entered]).to eq(20)
      expect(days["2026-07-15"]).to include(canopy_entered: nil)
      expect(days["2026-07-15"][:canopy]).to be < 90
      expect(inertia.props[:summary][:last_irrigation]).to include(date: "2026-07-08")
      expect(inertia.props[:summary][:tasks].find { |task| task[:kind] == "canopy" }).to include(last_date: "2026-07-06")

      get planting_path(planting)
      days = inertia.props[:days].index_by { |day| day[:date] }
      expect(days["2026-07-15"]).to include(canopy_entered: 90)
      expect(days["2026-07-12"]).to include(irrigation: 1.0)
    end

    it "drops a date that isn't an earlier day of the season from the URL, keeping the rest" do
      ["2026-07-20", "2026-07-25", "2026-06-30", "July 10", ""].each do |as_of|
        get planting_path(planting, as_of:)
        expect(response).to redirect_to(planting_path(planting))
      end
      follow_redirect!
      expect(inertia.props).to include(as_of: nil)
      expect(inertia.props[:summary]).to include(date: "2026-07-20")
    end

    it "is 404 for another group's planting" do
      other = create(:planting)
      get root_path
      get planting_path(other, as_of: "2026-07-10")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "editing a day" do
    let(:url) { field_day_path(field, "2026-07-08") }

    it "gives a part-field planting its own irrigation, readings and notes, and the field the rain (G.11)" do
      plot_field = create(:field, pivot:, name: "Arlington 525", area_acres: 4)
      plot = create(:planting, field: plot_field, partial: true, plot_length_ft: 100, plot_width_ft: 20,
        season_start: Date.new(2026, 5, 1), emergence_date: Date.new(2026, 5, 20), end_date: Date.new(2026, 9, 30))
      patch field_day_path(plot_field, "2026-07-08"),
        params: {day: {rain_in: 0.3, irrigation_in: 0.25, soil_moisture_pct: 14, notes: "Drip"}, planting_id: plot.id}
      expect(plot.planting_entries.sole).to have_attributes(irrigation_in: 0.25, soil_moisture_pct: 14, notes: "Drip")
      expect(plot_field.field_entries.sole).to have_attributes(rain_in: 0.3, irrigation_in: nil, soil_moisture_pct: nil)

      patch field_day_path(plot_field, "2026-07-08"), params: {day: {irrigation_in: "", soil_moisture_pct: "", notes: ""},
                                                               planting_id: plot.id}
      expect(plot.planting_entries).to be_empty
      expect(plot_field.field_entries.sole.rain_in).to eq(0.3)
    end

    it "records rain, irrigation, a moisture reading and notes, and clears them" do
      patch url, params: {day: {rain_in: 0.0, irrigation_in: 0.6, notes: " Gauge "}, planting_id: planting.id}
      expect(field.field_entries.sole).to have_attributes(rain_in: 0.0, irrigation_in: 0.6, soil_moisture_pct: nil, notes: "Gauge")

      patch url, params: {day: {soil_moisture_pct: 11}, planting_id: planting.id}
      expect(field.field_entries.sole).to have_attributes(rain_in: 0.0, soil_moisture_pct: 11)

      patch url, params: {day: {rain_in: nil, irrigation_in: nil, soil_moisture_pct: nil, notes: ""}}, as: :json
      expect(field.field_entries).to be_empty
    end

    it "records the planting's canopy reading as percent cover or LAI" do
      patch url, params: {day: {canopy: 35}, planting_id: planting.id}
      expect(planting.canopy_observations.sole).to have_attributes(date: Date.new(2026, 7, 8), pct_cover: 35, lai: nil)

      planting.update!(plant: create(:plant, canopy_model: "field_corn"), et_method: "lai")
      patch url, params: {day: {canopy: 1.5}, planting_id: planting.id}
      expect(planting.canopy_observations.sole).to have_attributes(pct_cover: nil, lai: 1.5)

      patch url, params: {day: {canopy: ""}, planting_id: planting.id}
      expect(planting.canopy_observations).to be_empty
    end

    it "rejects bad values without saving any of the day" do
      patch url, params: {day: {rain_in: -1, canopy: 150}, planting_id: planting.id}, headers: {"HTTP_REFERER" => field_path(field)}
      follow_redirect!
      expect(inertia.props[:errors]).to include("rain_in", "canopy")
      expect(field.field_entries).to be_empty
      expect(planting.canopy_observations).to be_empty
    end

    it "refuses a canopy reading outside the planting's season" do
      patch field_day_path(field, "2026-06-15"), params: {day: {canopy: 30}, planting_id: planting.id},
        headers: {"HTTP_REFERER" => field_path(field)}
      follow_redirect!
      expect(inertia.props[:errors]).to include("canopy" => ["is outside this planting's season"])
      expect(planting.canopy_observations).to be_empty
    end

    it "refuses a date that isn't one" do
      patch field_day_path(field, "2026-02-30"), params: {day: {rain_in: 0.5}}
      expect(response).to have_http_status(:bad_request)
      expect(field.field_entries).to be_empty
    end

    it "changes the balance on the next page load" do
      get planting_path(planting)
      before = inertia.props[:days].last[:ad]
      patch url, params: {day: {soil_moisture_pct: 5}, planting_id: planting.id}
      get planting_path(planting)
      expect(inertia.props[:days].last[:ad]).to be < before
    end
  end

  describe "the dashboard" do
    it "shows each farm's pivots, with a card per field and its status today" do
      create(:field, pivot:, name: "Bare")
      empty = create(:pivot, farm:, name: "A new pivot")
      get root_path
      farm_props = inertia.props[:farms].sole
      expect(farm_props[:name]).to eq(farm.name)
      expect(farm_props[:pivots].map { |p| [p[:name], p[:fields].size] }).to eq([[empty.name, 0], [pivot.name, 2]])
      cards = farm_props[:pivots].last[:fields].index_by { |card| card[:name] }
      summary = cards["North potatoes"][:plantings].sole
      expect(summary).to include(phase: "active", status: "ok", partial: false) # AD 1.05 of 1.2
      expect(summary[:recent].size).to eq(20)
      expect(summary[:tasks].select { |task| task[:due] }.map { |task| task[:todo] })
        .to eq(["Enter a soil moisture reading (none yet this season)", "Enter a percent cover reading (none yet this season)"])
      expect(cards["Bare"][:plantings]).to eq([])
    end

    # Dashboard/Show offers the guided setup when there are no farms; the props are all the server decides
    it "gives a new account's dashboard no farms" do
      sign_in create(:user)
      get root_path
      expect_inertia.to render_component("Dashboard/Show")
      expect(inertia.props).to include(farms: [], today: "2026-07-20")
    end
  end

  describe "pivot irrigation" do
    let!(:other_field) { create(:field, pivot:, name: "North corn", area_acres: 50) }

    it "creates, replaces by date, edits and deletes" do
      post pivot_irrigations_path(pivot), params: {pivot_irrigation: {date: "2026-07-10", inches: 0.8, field_ids: ["", field.id, other_field.id]}}
      irrigation = pivot.pivot_irrigations.sole
      expect(irrigation).to have_attributes(inches: 0.8, field_ids: nil) # every field: stored as all

      post pivot_irrigations_path(pivot), params: {pivot_irrigation: {date: "2026-07-10", inches: 0.7, field_ids: ["", field.id]}}
      expect(irrigation.reload).to have_attributes(inches: 0.7, field_ids: [field.id])

      patch pivot_irrigation_path(pivot, irrigation), params: {pivot_irrigation: {inches: "", run_hours: 12}}
      expect(irrigation.reload).to have_attributes(inches: nil, run_hours: 12)

      delete pivot_irrigation_path(pivot, irrigation)
      expect(pivot.pivot_irrigations).to be_empty
    end

    it "refuses an irrigation applied to no fields" do
      post pivot_irrigations_path(pivot), params: {pivot_irrigation: {date: "2026-07-10", inches: 0.8, field_ids: [""]}},
        headers: {"HTTP_REFERER" => pivot_path(pivot)}
      expect(pivot.pivot_irrigations).to be_empty
      follow_redirect!
      expect(inertia.props[:errors]).to include("field_ids")
    end

    it "lists a season's irrigation on the pivot page" do
      pivot.pivot_irrigations.create!(date: Date.new(2026, 7, 10), inches: 0.8)
      pivot.pivot_irrigations.create!(date: Date.new(2025, 7, 10), inches: 0.8)
      get pivot_path(pivot)
      expect(inertia.props[:irrigations].map { |i| i[:date] }).to eq(["2026-07-10"])
    end

    it "shows the week ahead in the pivot's weather zone, linking to it (G.12)" do
      pivot.weather_cell.weather_forecasts.create!(issued_at: 1.hour.ago, model: "ncep_nbm_conus",
        payload: {days: [{date: "2026-07-19", tmax_f: 80}, {date: "2026-07-20", tmax_f: 90, tmin_f: 70}]})
      get pivot_path(pivot)
      expect(inertia.props[:weather_zone]).to eq({"id" => pivot.weather_cell_id, "name" => pivot.name})
      expect(inertia.props[:forecast].map { |day| day[:date] }).to eq(["2026-07-20"])

      get pivot_path(pivot, year: 2025)
      expect(inertia.props[:forecast]).to eq([])
    end
  end

  describe "bulk daily entry" do
    let!(:other_field) { create(:field, pivot:, name: "North corn", area_acres: 50) }

    it "shows every pivot and field for a date with modeled rain" do
      get daily_entry_path(date: "2026-07-05")
      pivot_props = inertia.props[:farms].sole[:pivots].sole
      expect(pivot_props[:fields].map { |f| [f[:name], f[:rain_model]] }).to eq([["North corn", 0.4], ["North potatoes", 0.4]])
      expect(inertia.props[:date]).to eq("2026-07-05")
    end

    it "shows what's already entered for the date, and the crop in season" do
      field.field_entries.create!(date: Date.new(2026, 7, 5), rain_in: 0.3, notes: "gauge")
      pivot.pivot_irrigations.create!(date: Date.new(2026, 7, 5), inches: 0.8, field_ids: [field.id])
      get daily_entry_path(date: "2026-07-05")
      pivot_props = inertia.props[:farms].sole[:pivots].sole
      expect(pivot_props[:irrigation]).to include(inches: 0.8, field_ids: [field.id])
      fields = pivot_props[:fields].index_by { |f| f[:name] }
      expect(fields["North potatoes"]).to include(entry: {"rain_in" => 0.3, "irrigation_in" => nil, "soil_moisture_pct" => nil})
      expect(fields["North potatoes"][:plantings].map { |planting| planting[:plant_name] }).to eq(["Potato"])
      expect(fields["North corn"]).to include(plantings: [], entry: nil)
    end

    it "leaves out the modeled rain on a field that uses only entered rain (Q7)" do
      field.update!(use_model_precip: false)
      get daily_entry_path(date: "2026-07-05")
      fields = inertia.props[:farms].sole[:pivots].sole[:fields]
      expect(fields.map { |f| [f[:name], f[:rain_model]] }).to eq([["North corn", 0.4], ["North potatoes", nil]])
    end

    it "saves pivot irrigation and field entries for the day together" do
      patch daily_entry_path, params: {
        date: "2026-07-15",
        pivots: {pivot.id => {inches: "", run_hours: 10, field_ids: ["", other_field.id]}},
        fields: {field.id => {rain_in: 0.3, irrigation_in: "", soil_moisture_pct: ""}, other_field.id => {rain_in: "0"}}
      }
      expect(response).to redirect_to(daily_entry_path(date: "2026-07-15"))
      expect(pivot.pivot_irrigations.sole).to have_attributes(run_hours: 10, field_ids: [other_field.id])
      expect(field.field_entries.sole).to have_attributes(rain_in: 0.3, irrigation_in: nil)
      expect(other_field.field_entries.sole.rain_in).to eq(0.0)

      # Blank amounts remove the pivot's irrigation and empty entries
      patch daily_entry_path, params: {date: "2026-07-15", pivots: {pivot.id => {inches: "", run_hours: ""}},
                                       fields: {field.id => {rain_in: ""}}}
      expect(pivot.pivot_irrigations).to be_empty
      expect(field.field_entries).to be_empty
    end

    it "ignores a pivot or field sent without values" do
      patch daily_entry_path, params: {date: "2026-07-15", pivots: {pivot.id => "1"}, fields: {field.id => "0.3"}}
      expect(response).to redirect_to(daily_entry_path(date: "2026-07-15"))
      expect(pivot.pivot_irrigations).to be_empty
      expect(field.field_entries).to be_empty
    end

    it "saves nothing when any value is invalid" do
      patch daily_entry_path, params: {date: "2026-07-15", pivots: {pivot.id => {inches: 0.5}},
                                       fields: {field.id => {soil_moisture_pct: 140}}}
      expect(pivot.pivot_irrigations).to be_empty
      follow_redirect!
      expect(inertia.props[:errors]).to include("fields.#{field.id}.soil_moisture_pct")
    end
  end
end

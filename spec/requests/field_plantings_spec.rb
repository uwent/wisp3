require "rails_helper"

# PLAN.md Phase 8 G.11's pages: the field page (the land, its plantings and its own entries), each
# planting's page, cards per planting, the planting form's replace and size limit, and the digest.
RSpec.describe "Fields with several plantings", type: :request do
  let(:user) { create(:user) }
  let(:group) { user.groups.first }
  let(:pivot) { create(:pivot, farm: create(:farm, group:)) }
  let(:field) { create(:field, pivot:, name: "Arlington 525", area_acres: 2) }
  let(:season) { {season_start: Date.new(2026, 7, 1), emergence_date: Date.new(2026, 7, 1), end_date: Date.new(2026, 9, 30)} }

  def plot(name = "Soybean", length: 100, width: 20, **attributes)
    create(:planting, field:, plant: create(:plant, name:), partial: true, plot_length_ft: length, plot_width_ft: width,
      **season, **attributes)
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
    it "lists the season's plantings with their status, and the field's own rain and irrigation" do
      soy, corn = plot("Soybean"), plot("Corn", length: 50)
      field.field_entries.create!(date: Date.new(2026, 7, 10), irrigation_in: 0.6, rain_in: 0.3)
      pivot.pivot_irrigations.create!(date: Date.new(2026, 7, 12), inches: 0.5)

      get field_path(field)
      expect_inertia.to render_component("Fields/Show")
      props = inertia.props
      expect(props[:year]).to eq(2026)
      expect(props[:plantings].map { |s| s[:planting_id] }).to eq([soy.id, corn.id])
      expect(props[:plantings].first).to include(phase: "active", partial: true, plot_length_ft: 100.0, plot_width_ft: 20.0)
      expect(props[:field][:plantings].size).to eq(2)
      days = props[:days].index_by { |day| day[:date] }
      expect(props[:days].first[:date]).to eq("2026-07-20") # newest first, through today
      expect(days["2026-07-05"]).to include(rain: 0.4, rain_source: "model")
      expect(days["2026-07-10"]).to include(rain: 0.3, rain_source: "entered", irrigation: 0.6, irrigation_source: "entered")
      expect(days["2026-07-12"]).to include(irrigation: 0.5, irrigation_source: "pivot")
    end

    it "saves the field's own entry from its grid, without a planting" do
      plot
      patch field_day_path(field, "2026-07-08"), params: {day: {irrigation_in: 0.7}}, headers: {"HTTP_REFERER" => field_path(field)}
      expect(field.field_entries.sole).to have_attributes(irrigation_in: 0.7)
      expect(PlantingEntry.count).to eq(0)
    end

    it "shows another season by ?year=" do
      create(:planting, field:, season_start: Date.new(2025, 4, 1), emergence_date: Date.new(2025, 5, 1), end_date: Date.new(2025, 9, 1))
      plot
      get field_path(field, year: 2025)
      expect(inertia.props[:plantings].sole).to include(phase: "ended")
      expect(inertia.props[:days].first[:date]).to eq("2025-09-01")
    end
  end

  describe "a plot's page" do
    it "shows the field's irrigation as from the field, and the field's amount under the plot's own" do
      soy = plot
      field.field_entries.create!(date: Date.new(2026, 7, 10), irrigation_in: 0.6)
      field.field_entries.create!(date: Date.new(2026, 7, 11), irrigation_in: 0.4)
      soy.planting_entries.create!(date: Date.new(2026, 7, 11), irrigation_in: 0.2)

      get planting_path(soy)
      expect_inertia.to render_component("Plantings/Show")
      expect(inertia.props[:planting]).to include(partial: true, exceeds_field_area: false)
      days = inertia.props[:days].index_by { |day| day[:date] }
      expect(days["2026-07-10"]).to include(irrigation: 0.6, irrigation_source: "field", field_inches: 0.6)
      expect(days["2026-07-11"]).to include(irrigation: 0.2, irrigation_source: "entered", field_inches: 0.4)
    end

    it "warns when the plots together cover more than the field" do
      plot(length: 300, width: 200) # 1.38 ac
      big = plot("Corn", length: 300, width: 200)
      get planting_path(big)
      expect(inertia.props[:planting][:exceeds_field_area]).to be(true)
    end
  end

  describe "the dashboard and digest" do
    it "gives a field of plots a summary per planting" do
      soy, corn = plot("Soybean"), plot("Corn", length: 50)
      get root_path
      card = inertia.props[:farms].sole[:pivots].sole[:fields].sole
      expect(card[:name]).to eq("Arlington 525")
      expect(card[:plantings].map { |s| s[:planting_id] }).to eq([soy.id, corn.id])
      expect(card[:plantings].map { |s| s[:area_acres] }).to all(be > 0)
    end

    it "lists the plots together once their season has ended, but only the nearest of a succession" do
      soy, corn = plot("Soybean"), plot("Corn", length: 50, end_date: Date.new(2026, 8, 31))
      garden = create(:field, pivot:, name: "Garden")
      create(:planting, field: garden, season_start: Date.new(2026, 4, 1), emergence_date: Date.new(2026, 4, 10), end_date: Date.new(2026, 6, 30))
      squash = create(:planting, field: garden, season_start: Date.new(2026, 7, 1), emergence_date: Date.new(2026, 7, 8),
        end_date: Date.new(2026, 9, 30))
      statuses = FieldStatuses.for(Field.where(id: [field.id, garden.id]).includes(:soil_type, pivot: :weather_cell,
        plantings: [:plant, :canopy_observations, :soil_type]), today: Date.new(2026, 11, 10))
      expect(statuses[field.id].map(&:planting)).to eq([soy, corn])
      expect(statuses[garden.id].map(&:planting)).to eq([squash])
    end

    it "lists each planting under its field, linking to its page, and counts the field once" do
      user.update!(digest_scope: "all")
      soy, corn = plot("Soybean"), plot("Corn", length: 50)
      digest = DailyDigest.new(user)
      expect(digest.all_entries.map { |entry| entry.status.planting }).to contain_exactly(soy, corn)
      expect(digest.counts).to have_attributes(fields: 1, covered_fields: 1, planted: 1)
      expect(digest.plot(soy)).to eq("100 × 20 ft (0.05 ac)")

      mail = DigestMailer.daily(digest)
      html = mail.html_part.body.to_s
      expect(html).to include("Soybean, 100 × 20 ft (0.05 ac)", "Corn, 50 × 20 ft (0.02 ac)")
      expect(html).to include("/plantings/#{soy.id}?operation=#{group.id}")
    end
  end

  describe "the planting form" do
    let(:plant) { create(:plant) }

    it "refuses part of a field larger than the field" do
      post plantings_path, params: {planting: {field_id: field.id, plant_id: plant.id, partial: "true", area_acres: 3, **season}},
        headers: {"HTTP_REFERER" => setup_url}
      follow_redirect!
      expect(inertia.props[:errors]).to include("area_acres" => ["Area is more than the field's 2 acres"])
      expect(field.plantings).to be_empty
    end

    it "replaces an overlapping planting, ending it the day before" do
      early = create(:planting, field:, season_start: Date.new(2026, 4, 1), emergence_date: Date.new(2026, 4, 15),
        end_date: Date.new(2026, 9, 30))
      post plantings_path, params: {planting: {field_id: field.id, plant_id: plant.id, season_start: "2026-07-01",
                                               emergence_date: "2026-07-08", end_date: "2026-09-30"}, replace: "1"}
      expect(field.plantings.count).to eq(2)
      expect(early.reload.end_date).to eq(Date.new(2026, 6, 30))
    end

    it "leaves the other planting as it was when the new one can't be saved" do
      early = create(:planting, field:, season_start: Date.new(2026, 4, 1), emergence_date: Date.new(2026, 4, 15),
        end_date: Date.new(2026, 9, 30))
      post plantings_path, params: {planting: {field_id: field.id, plant_id: plant.id, season_start: "2026-07-01",
                                               emergence_date: "2026-07-08", end_date: "2026-06-01"}, replace: "1"}
      expect(early.reload.end_date).to eq(Date.new(2026, 9, 30))
      expect(field.plantings.count).to eq(1)
    end

    it "doesn't end a plot when adding another plot" do
      soy = plot
      post plantings_path, params: {planting: {field_id: field.id, plant_id: plant.id, partial: "true", area_acres: 0.5,
                                               season_start: "2026-08-01", emergence_date: "2026-08-08", end_date: "2026-09-30"}, replace: "1"}
      expect(soy.reload.end_date).to eq(Date.new(2026, 9, 30))
      expect(field.plantings.count).to eq(2)
    end
  end
end

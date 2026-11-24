require "rails_helper"

# The public example farm (ExampleMode): anyone may view it, read-only, as of its day;
# it never reaches another group's records and never writes
RSpec.describe "Example mode", type: :request do
  let(:example) { create(:group, name: "Example farm", example_as_of: Date.new(2026, 7, 20)) }
  let(:example_system) { create(:system, farm: create(:farm, group: example)) }
  let(:example_field) { create(:field, system: example_system) }
  let!(:example_planting) { create(:planting, field: example_field) }
  let(:user) { create(:user) }
  let(:their_field) { create(:field, system: create(:system, farm: create(:farm, group: user.groups.first))) }

  before { travel_to Date.new(2026, 11, 17) }

  def enter
    get example_path
    expect(response).to redirect_to(root_path)
    follow_redirect!
  end

  it "shows the example's dashboard to anyone, as of its day, with its bar" do
    get root_path
    expect_inertia.to render_component("Pages/Home")

    enter
    expect_inertia.to render_component("Dashboard/Show")
    expect(inertia.props[:today]).to eq("2026-07-20")
    expect(inertia.props[:example]).to eq("as_of" => "2026-07-20")
    expect(inertia.props[:auth][:group][:name]).to eq("Example farm")
    expect(inertia.props[:getting_started]).to be_nil

    # Its pages, with the planting as of its day (time travel's view, which has no other day)
    get map_path
    expect_inertia.to render_component("Map/Show")
    get field_path(example_field)
    expect_inertia.to render_component("Fields/Show")
    get planting_path(example_planting)
    expect(inertia.props[:as_of]).to eq("2026-07-20")
    expect(inertia.props[:travel_dates]).to be_nil
    get system_path(example_system)
    expect_inertia.to render_component("Systems/Show")
    get weather_zones_path
    expect_inertia.to render_component("WeatherZones/Index")
    get about_path
    expect(inertia.props[:example]).to be_present
  end

  it "reaches only the example's records" do
    enter
    get field_path(their_field)
    expect(response).to have_http_status(:not_found)
    get planting_path(create(:planting, field: their_field))
    expect(response).to have_http_status(:not_found)
  end

  it "writes nothing, and sends other pages back to the example's dashboard" do
    enter
    patch field_path(example_field), params: {field: {name: "Mine now"}}
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include("can only be viewed")
    post system_irrigations_path(example_system), params: {irrigation: {date: "2026-07-01", fields: {example_field.id => "1"}}}
    expect(response).to redirect_to(root_path)
    delete system_irrigation_path(example_system, "2026-07-01")
    expect(response).to redirect_to(root_path)
    expect(example_field.field_entries).to be_empty
    expect(example_field.reload.name).not_to eq("Mine now")

    [setup_path, daily_entry_path, daily_entry_week_path, alerts_path, settings_path, group_path, admin_users_path].each do |path|
      get path
      expect(response).to redirect_to(root_path), path
    end
  end

  # Every signed-in route, read from the routes, so a new one is covered as soon as it's added: only
  # the GET actions a controller lists with allow_example answer; the rest go back to the dashboard
  # having written nothing
  describe "every route" do
    routes = Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller] or next
      klass = "#{controller}_controller".camelize.safe_constantize
      next unless klass && klass < AuthenticatedController
      {verb: route.verb.downcase.to_sym, spec: route.path.spec.to_s.delete_suffix("(.:format)"), controller:,
       action: route.defaults[:action], allowed: route.verb == "GET" && klass.example_actions.include?(route.defaults[:action])}
    end.uniq.freeze

    # The example's own records, so a write that got through would have something to change
    def path_for(route)
      ids = {"farms" => example_system.farm_id, "systems" => example_system.id, "fields" => example_field.id,
             "plantings" => example_planting.id, "weather_zones" => example_system.weather_cell_id}
      route[:spec].gsub(":date", "2026-07-01").gsub(":location", example_system.weather_cell.location)
        .gsub(":system_id", example_system.id.to_s).gsub(":field_id", example_field.id.to_s)
        .gsub(":planting_id", example_planting.id.to_s).gsub(":id", ids.fetch(route[:controller], 1).to_s).gsub(/:\w+/, "1")
    end

    def counts = [Farm, IrrigationSystem, Field, Planting, FieldEntry, PlantingEntry, IrrigationGroup, Group, Membership, User].map(&:count)

    it "finds the routes, and every action allowed is a GET route's" do
      expect(routes.size).to be > 60
      expect(routes.count { |route| route[:allowed] }).to be >= 12
      listed = AuthenticatedController.descendants.flat_map { |klass| klass.example_actions.map { |action| [klass.controller_path, action] } }
      expect(listed - routes.select { |route| route[:allowed] }.map { |route| [route[:controller], route[:action]] }).to be_empty
    end

    it "sends everything not allowed back to the dashboard, writing nothing" do
      enter
      example_field.update_columns(name: "As seeded")
      refused = routes.reject { |route| route[:allowed] }
      expect { refused.each { |route| public_send(route[:verb], path_for(route)) } }.not_to change { counts }
      refused.each do |route|
        public_send(route[:verb], path_for(route))
        expect(response).to redirect_to(root_path), "#{route[:verb].upcase} #{path_for(route)}: #{response.status}"
        expect(flash[:alert]).to include("can only be viewed")
      end
      expect(example_field.reload.name).to eq("As seeded")
      expect(example.reload.name).to eq("Example farm")
    end

    it "answers the allowed pages and downloads" do
      enter
      routes.select { |route| route[:allowed] }.each do |route|
        get path_for(route)
        label = "GET #{path_for(route)}: #{response.status}"
        expect(response.status).to be < 400, label
        expect(flash[:alert].to_s).not_to include("can only be viewed"), label
      end
    end
  end

  it "shows the example to a signed-in user until they leave it or sign in again" do
    sign_in user
    get root_path
    expect(inertia.props[:auth][:group][:id]).to eq(user.groups.first.id)

    enter
    expect(inertia.props[:auth][:group][:name]).to eq("Example farm")
    expect(inertia.props[:auth][:owner]).to be(false)
    get setup_path
    expect(response).to redirect_to(root_path)

    delete example_path
    follow_redirect!
    expect(inertia.props[:example]).to be_nil
    expect(inertia.props[:auth][:group][:id]).to eq(user.groups.first.id)
  end

  it "ends once signed out visitors leave, and without an example there's none to enter" do
    enter
    delete example_path
    follow_redirect!
    expect_inertia.to render_component("Pages/Home")

    example.destroy!
    get example_path
    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect_inertia.to render_component("Pages/Home")
  end

  it "asks a visitor loading too many pages to wait" do
    enter
    allow(ExampleMode).to receive(:limit).and_return(instance_double(WindowLimit, allow!: false, retry_message: "Please try again in 1 minute."))
    get map_path
    expect(response).to have_http_status(:too_many_requests)
  end
end

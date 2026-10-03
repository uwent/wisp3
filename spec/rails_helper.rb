require "simplecov"
SimpleCov.start "rails" do
  skip "/spec/"
end

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
require "inertia_rails/rspec"
require "webmock/rspec"

Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# Outbound HTTP is never allowed in specs (Vite's dev server check uses localhost)
WebMock.disable_net_connect!(allow_localhost: true)

# Specs use the free Open-Meteo API whatever a developer's .env holds; specs of the commercial
# API pass api_key: explicitly
ENV.delete("OPEN_METEO_API_KEY")

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("spec/fixtures")]
  config.use_transactional_fixtures = true
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include ActiveJob::TestHelper
  config.include ActiveSupport::Testing::TimeHelpers

  # Rate limits and Rack::Attack counters live in the cache
  config.before { Rails.cache.clear }

  # Specs create the plants and soil types they need. db:prepare seeds the reference data into a
  # freshly created test database (as on CI), so start every run without it.
  config.before(:suite) do
    Plant.delete_all
    SoilType.delete_all
  end
end

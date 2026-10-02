# Staging mirrors production (dev.wisp.cals.wisc.edu) with more verbose logs.
require_relative "production"

Rails.application.configure do
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "debug")
end

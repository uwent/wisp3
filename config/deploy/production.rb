# The new production server for the 2027 season (plan.md §12). Set its hostname when it's ready.
production_host = ENV["PRODUCTION_HOST"] or raise "Set PRODUCTION_HOST to the new production server's hostname"
server production_host, user: "deploy", roles: %w[app web db], port: 216

set :rails_env, "production"
append :linked_files, "config/credentials/production.key"
set :app_host, "wisp.cals.wisc.edu"
set :puma_port, 3100
set :default_env, {"APP_HOST" => fetch(:app_host)}

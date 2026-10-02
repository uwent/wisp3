# dev.wisp.cals.wisc.edu (the staging host also runs ag-weather and the legacy WISP staging app)
server "dev.agweather.cals.wisc.edu", user: "deploy", roles: %w[app web db], port: 216

set :rails_env, "staging"
append :linked_files, "config/credentials/staging.key"
set :app_host, "dev.wisp.cals.wisc.edu"
set :puma_port, 3100
set :default_env, {"APP_HOST" => fetch(:app_host)}

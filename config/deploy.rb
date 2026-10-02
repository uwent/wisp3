# Deploy with `cap staging deploy` (or `cap production deploy`). First-time server setup is in
# docs/deployment.md.
set :application, "wisp3"
set :repo_url, "https://github.com/uwent/wisp3.git"
set :branch, ENV.fetch("BRANCH", "main")
set :deploy_to, "/home/deploy/wisp3"
set :keep_releases, 5

set :rbenv_type, :user
set :rbenv_ruby, File.read(".ruby-version").strip

# Each stage also links its Rails credentials key (see config/deploy/<stage>.rb)
append :linked_dirs, "log", "tmp/pids", "tmp/cache", "tmp/sockets", "node_modules"

# Loads schemas for the cache and queue databases on first deploy, migrates after that
set :migration_command, "db:prepare"
set :migration_role, :db

# Restart the systemd user services (installed with `cap <stage> systemd:install`)
after "deploy:publishing", "systemd:restart"

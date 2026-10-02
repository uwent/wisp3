source "https://rubygems.org"

gem "rails", "~> 8.1.3"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "bootsnap", require: false
gem "tzinfo-data", platforms: %i[windows jruby]

gem "solid_cache" # Rails.cache backed by Postgres
gem "solid_queue" # background + recurring jobs backed by Postgres

gem "devise" # email/password accounts; magic links are built on top (app/controllers/magic_links_controller.rb)
gem "inertia_rails" # serves Svelte pages from Rails controllers
gem "vite_rails" # builds the Svelte/TS/Tailwind frontend
gem "alba" # JSON serializers for page props
gem "typelizer" # generates TypeScript types (serializers) and route helpers for the frontend
gem "rack-attack" # rate limiting

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "standard", require: false
end

group :development do
  gem "web-console"
  gem "letter_opener_web" # view sent mail at /letter_opener
  gem "capistrano", require: false
  gem "capistrano-rails", require: false
  gem "capistrano-bundler", require: false
  gem "capistrano-rbenv", require: false
  gem "ed25519", require: false # ssh keys for capistrano
  gem "bcrypt_pbkdf", require: false
end

group :test do
  gem "webmock"
  gem "simplecov", require: false
end

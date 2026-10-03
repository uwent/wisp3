# Load plants and soil types (db/reference/*.yml) on every deploy; idempotent (ReferenceData)
namespace :deploy do
  desc "Load reference data"
  task :reference_data do
    on primary(fetch(:migration_role)) do
      within release_path do
        with rails_env: fetch(:rails_env) do
          execute :rake, "db:seed"
        end
      end
    end
  end
end

after "deploy:migrate", "deploy:reference_data"

# WISP 3 runs as two systemd *user* services owned by the deploy user (requires
# `loginctl enable-linger deploy` on the server), so deploys restart them without sudo.
namespace :systemd do
  def units
    {"web" => "#{fetch(:application)}-web", "jobs" => "#{fetch(:application)}-jobs"}
  end

  desc "Install or update the systemd user units and enable them"
  task :install do
    on roles(:app) do
      unit_dir = "/home/#{host.user}/.config/systemd/user"
      execute :mkdir, "-p", unit_dir
      units.each do |template, unit|
        rendered = ERB.new(File.read("config/systemd/#{template}.service.erb")).result(binding)
        upload! StringIO.new(rendered), "#{unit_dir}/#{unit}.service"
      end
      execute :systemctl, "--user", "daemon-reload"
      execute :systemctl, "--user", "enable", *units.values
    end
  end

  desc "Restart the web and job services"
  task :restart do
    on roles(:app) do
      execute :systemctl, "--user", "restart", *units.values
    end
  end

  desc "Show service status"
  task :status do
    on roles(:app) do
      units.each_value { |unit| puts capture(:systemctl, "--user", "status", unit, "--no-pager", raise_on_non_zero_exit: false) }
    end
  end
end

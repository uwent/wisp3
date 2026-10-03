# WISP 3 runs as two systemd *user* services owned by the deploy user (requires
# `loginctl enable-linger deploy` on the server), so deploys restart them without sudo.
namespace :systemd do
  def units
    {"web" => "#{fetch(:application)}-web", "jobs" => "#{fetch(:application)}-jobs"}
  end

  # Non-interactive SSH sessions don't set XDG_RUNTIME_DIR, without which `systemctl --user`
  # fails with "Failed to connect to bus: No medium found".
  def user_systemctl(*args, **options)
    with xdg_runtime_dir: "/run/user/#{capture(:id, "-u")}" do
      return capture(:systemctl, "--user", *args, **options) if options.delete(:capture)
      execute :systemctl, "--user", *args, **options
    end
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
      user_systemctl "daemon-reload"
      user_systemctl "enable", *units.values
    end
  end

  desc "Restart the web and job services"
  task :restart do
    on roles(:app) do
      user_systemctl "restart", *units.values
    end
  end

  desc "Show service status"
  task :status do
    on roles(:app) do
      units.each_value { |unit| puts user_systemctl("status", unit, "--no-pager", capture: true, raise_on_non_zero_exit: false) }
    end
  end
end

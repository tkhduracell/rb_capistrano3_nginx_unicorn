require 'capistrano'

namespace :load do
  task :defaults do
    def set_default(name, *args, &block)
      set(name, *args, &block) unless exists?(name)
    end

    set_default(:templates_path, "config/deploy/templates")

    set_default(:nginx_server_name) { Capistrano::CLI.ui.ask "Nginx server name: " }
    set_default(:nginx_use_ssl, false)
    set_default(:nginx_ssl_certificate) { "#{nginx_server_name}.crt" }
    set_default(:nginx_ssl_certificate_key) { "#{nginx_server_name}.key" }
    set_default(:nginx_upload_local_certificate) { true }
    set_default(:nginx_ssl_certificate_local_path) {Capistrano::CLI.ui.ask "Local path to ssl certificate: "}
    set_default(:nginx_ssl_certificate_key_local_path) {Capistrano::CLI.ui.ask "Local path to ssl certificate key: "}

    set_default(:unicorn_pid) { "#{current_path}/tmp/pids/unicorn.pid" }
    set_default(:unicorn_config) { "#{shared_path}/config/unicorn.rb" }
    set_default(:unicorn_log) { "#{shared_path}/log/unicorn.log" }
    set_default(:unicorn_user) { user }
    set_default(:unicorn_workers) { Capistrano::CLI.ui.ask "Number of unicorn workers: " }
  end
end

namespace :nginx do
  desc "Setup nginx configuration for this application"
  task :setup, roles: :web do
    template("nginx_conf.erb", "/tmp/#{application}")
    on roles(:app) do
      execute :run, "#{sudo} mv /tmp/#{application} /etc/nginx/sites-available/#{application}"
      execute :run, "#{sudo} ln -fs /etc/nginx/sites-available/#{application} /etc/nginx/sites-enabled/#{application}"

      if nginx_use_ssl
        if nginx_upload_local_certificate
          put File.read(nginx_ssl_certificate_local_path), "/tmp/#{nginx_ssl_certificate}"
          put File.read(nginx_ssl_certificate_key_local_path), "/tmp/#{nginx_ssl_certificate_key}"

          execute :run, "#{sudo} mv /tmp/#{nginx_ssl_certificate} /etc/ssl/certs/#{nginx_ssl_certificate}"
          execute :run, "#{sudo} mv /tmp/#{nginx_ssl_certificate_key} /etc/ssl/private/#{nginx_ssl_certificate_key}"
        end

        execute :run, "#{sudo} chown root:root /etc/ssl/certs/#{nginx_ssl_certificate}"
        execute :run, "#{sudo} chown root:root /etc/ssl/private/#{nginx_ssl_certificate_key}"
      end
    end
  end

  after "deploy:setup", "nginx:setup"
  after "deploy:setup", "nginx:reload"

  desc "Reload nginx configuration"
  task :reload, roles: :web do
    on roles(:app) do
      execute :run, "#{sudo} /etc/init.d/nginx reload"
    end
  end
end

namespace :unicorn do
  desc "Setup Unicorn initializer and app configuration"
  task :setup, roles: :app do
    on roles(:app) do
      execute :run, "mkdir -p #{shared_path}/config"
      template "unicorn.rb.erb", unicorn_config
      template "unicorn_init.erb", "/tmp/unicorn_init"
      execute :run, "chmod +x /tmp/unicorn_init"
      execute :run, "#{sudo} mv /tmp/unicorn_init /etc/init.d/unicorn_#{application}"
      execute :run, "#{sudo} update-rc.d -f unicorn_#{application} defaults"
    end
  end

  after "deploy:setup", "unicorn:setup"

end

namespace :deploy do
  %w[start stop restart].each do |command|
    desc "#{command} unicorn"
    task command, roles: :app do
      on roles(:app) do
        execute :run, "service unicorn_#{application} #{command}"
      end
    end
  end
end

desc "Setup logs rotation for nginx and unicorn"
task :logrotate, roles: [:web, :app] do
  template("logrotate.erb", "/tmp/#{application}_logrotate")
  on roles(:app) do
    execute :run, "#{sudo} mv /tmp/#{application}_logrotate /etc/logrotate.d/#{application}"
    execute :run, "#{sudo} chown root:root /etc/logrotate.d/#{application}"
  end
end

after "deploy:setup", "logrotate"

def template(template_name, target)
  config_file = "#{templates_path}/#{template_name}"
  # if no customized file, proceed with default
  unless File.exists?(config_file)
    config_file = File.join(File.dirname(__FILE__), "../../generators/capistrano/nginx_unicorn/templates/#{template_name}")
  end
  put ERB.new(File.read(config_file)).result(binding), target
end


#
# Cookbook Name:: monit-ng
# Recipe:: source
#

source = node['monit']['source']

include_recipe 'apt' if platform_family?('debian')
include_recipe 'build-essential'

source['build_deps'].each do |build_dep|
  package build_dep
end

source_url = "#{source['url']}/monit-#{source['version']}.tar.gz"
download_path = Chef::Config['file_cache_path'] || '/tmp'
source_file_path = "#{download_path}/monit-#{source['version']}.tar.gz"
build_root = "#{download_path}/monit-#{source['version']}"

monit_bin = "#{source['prefix']}/bin/monit"
opts = "--prefix=#{source['prefix']}"
if platform_family?('debian') && source['version'].to_f < 5.6
  opts += " --with-ssl-lib-dir=/usr/lib/#{node['kernel']['machine']}-linux-gnu"
end

execute 'compile-source' do
  cwd build_root
  command <<-EOC
    ./configure #{opts} && make && make install
  EOC
  action :nothing
end

execute 'extract-source-archive' do
  cwd download_path
  command <<-EOC
    tar xzf #{::File.basename(source_file_path)} -C #{download_path}
  EOC
  action :nothing
  notifies :run, 'execute[compile-source]', :immediately
end

remote_file 'source-archive' do
  source source_url
  path source_file_path
  checksum source['checksum']
  path source_file_path
  backup false
  notifies :run, 'execute[extract-source-archive]', :immediately
end

# this is the upstream default config
# path. we link it to the platform
# default rather than patching the source,
# which would require carrying multiple
# patches for different versions; this
# also allows calling monit without passing
# the path to the global config file as an argument
link '/etc/monitrc' do
  to node['monit']['conf_file']
  not_if { node['monit']['conf_file'] == '/etc/monitrc' }
end

# Configure service
selected_provider = node['monit']['svc_provider'].inspect

file '/etc/init.d/monit' do
  action :nothing
end

execute 'reload-init' do
  case selected_provider
  when 'Chef::Provider::Service::Systemd'
    command 'systemctl daemon-reload'
  when 'Chef::Provider::Service::Upstart'
    command 'initctl reload-configuration'
  end
  subscribes :run, 'template[monit-init]', :immediately
  only_if do
    selected_provider == 'Chef::Provider::Service::Systemd' ||
      selected_provider == 'Chef::Provider::Service::Upstart'
  end
  action :nothing
end

template 'monit-init' do
  case selected_provider
  when 'Chef::Provider::Service::Systemd'
    source 'monit.systemd.erb'
    path '/lib/systemd/system/monit.service'
    mode '0644'
    notifies :delete, 'file[/etc/init.d/monit]', :immediately
  when 'Chef::Provider::Service::Upstart'
    source 'monit.upstart.erb'
    path '/etc/init/monit.conf'
    mode '0644'
    notifies :delete, 'file[/etc/init.d/monit]', :immediately
  else
    source 'monit.sysv.erb'
    path '/etc/init.d/monit'
    mode '0755'
  end
  variables(
    :platform_family => node['platform_family'],
    :binary          => monit_bin,
    :conf_file       => node['monit']['conf_file'],
  )
end

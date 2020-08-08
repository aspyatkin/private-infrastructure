resource_name :private_dns

property :cookbook, String, default: 'private'
property :packages, Array, default: %w[dnsmasq]
property :service_name, String, default: 'dnsmasq'
property :service_conf_file, String, default: '/etc/dnsmasq.conf'
property :service_conf_dir, String, default: '/etc/dnsmasq.d'

property :listen_address, String, required: true
property :bind_interfaces, [TrueClass, FalseClass], default: false
property :forward_servers, Array, default: %w[8.8.8.8 1.1.1.1 8.8.4.4 1.0.0.1]
property :records, Array, default: %w[]

property :nameserver, [String, NilClass], default: nil

default_action :install

action :install do
  new_resource.packages.each do |pkg_name|
    package pkg_name do
      action :install
    end
  end

  service new_resource.service_name do
    action 'nothing'
  end

  replace_or_add 'update resolver config' do
    path new_resource.service_conf_file
    pattern "#conf-dir=#{new_resource.service_conf_dir}/,*.conf"
    line "conf-dir=#{new_resource.service_conf_dir}/,*.conf"
    replace_only true
    action :edit
    notifies :restart, "service[#{new_resource.service_name}]", :delayed
  end

  template ::File.join(new_resource.service_conf_dir, 'default.conf') do
    cookbook new_resource.cookbook
    source 'dnsmasq/default.conf.erb'
    variables(
      listen_address: new_resource.listen_address,
      bind_interfaces: new_resource.bind_interfaces,
      forward_servers: new_resource.forward_servers
    )
    mode 0o664
    action :create
    notifies :restart, "service[#{new_resource.service_name}]", :delayed
  end

  template ::File.join(new_resource.service_conf_dir, 'records.conf') do
    cookbook new_resource.cookbook
    source 'dnsmasq/records.conf.erb'
    variables(
      records: new_resource.records
    )
    mode 0o664
    action :create
    notifies :restart, "service[#{new_resource.service_name}]", :delayed
  end

  service 'systemd-resolved' do
    action :nothing
  end

  replace_or_add 'disable systemd-resolved' do
    path '/etc/systemd/resolved.conf'
    pattern '#DNSStubListener='
    line 'DNSStubListener=no'
    replace_only true
    action :edit
    notifies :restart, 'service[systemd-resolved]', :immediately
  end

  static_resolv_conf = '/lib/systemd/resolv.conf'
  system_resolv_conf = '/etc/resolv.conf'

  file static_resolv_conf do
    content "nameserver #{new_resource.nameserver.nil? ? new_resource.listen_address : new_resource.nameserver}"
    mode 0o644
    action :create
  end

  execute "ln -sf #{static_resolv_conf} #{system_resolv_conf}" do
    action :run
    not_if { ::File.realpath(system_resolv_conf) == static_resolv_conf }
  end

  service new_resource.service_name do
    action %i[enable start]
  end
end

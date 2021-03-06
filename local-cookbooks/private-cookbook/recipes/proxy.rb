require 'json'

{
  'net.ipv4.ip_forward' => 1
}.each do |sysctl_key, sysctl_value|
  sysctl sysctl_key do
    value sysctl_value
    action :apply
  end
end

apt_update 'default' do
  action :update
  notifies :install, 'build_essential[default]', :immediately
end

build_essential 'default' do
  action :nothing
end

locale 'en' do
  lang 'en_US.utf8'
  lc_all 'en_US.utf8'
  action :update
end

include_recipe 'ntp::default'

node.default['firewall']['iptables']['defaults'][:ruleset] = {
  '*filter' => 1,
  ':INPUT DROP' => 2,
  ':FORWARD ACCEPT' => 3,
  ':OUTPUT ACCEPT_FILTER' => 4,
  '-N fail2ban' => 45,
  '-A fail2ban -j RETURN' => 45,
  '-A INPUT -j fail2ban' => 45,
  'COMMIT_FILTER' => 100,
  '*nat' => 101,
  ':PREROUTING ACCEPT' => 102,
  ':POSTROUTING ACCEPT' => 103,
  ':OUTPUT ACCEPT_NAT' => 104,
  'COMMIT_NAT' => 200
}
include_recipe 'firewall::default'

opt = node['private']
secret = ::ChefCookbook::Secret::Helper.new(node)

ssmtp 'default' do
  sender_email opt['ssmtp']['sender_email']
  smtp_host opt['ssmtp']['smtp_host']
  smtp_port opt['ssmtp']['smtp_port']
  smtp_username opt['ssmtp']['smtp_username']
  smtp_password secret.get("smtp:password:#{opt['ssmtp']['smtp_username']}", prefix_fqdn: false)
  smtp_enable_starttls opt['ssmtp']['smtp_enable_starttls']
  smtp_enable_ssl opt['ssmtp']['smtp_enable_ssl']
  from_line_override opt['ssmtp']['from_line_override']
  action :install
end

package 'fail2ban' do
  action :install
end

service 'fail2ban' do
  action :nothing
end

template '/etc/fail2ban/jail.local' do
  source 'fail2ban/jail.local.erb'
  owner 'root'
  group node['root_group']
  mode 0o644
  variables(
    chain: 'fail2ban',
    action: 'action_',
    destemail: opt['fail2ban']['destemail'],
    sender: opt['fail2ban']['sender'],
    sendername: opt['fail2ban']['sendername'],
    jail: opt['fail2ban']['jail']
  )
  action :create
  notifies :restart, 'service[fail2ban]', :delayed
end

opt_enable_ipv6 = node['firewall']['ipv6_enabled']

instance = ::ChefCookbook::Instance::Helper.new(node)
secret = ::ChefCookbook::Secret::Helper.new(node)

include_recipe 'sockd::default'

firewall_rule 'socks5' do
  port 1080
  source '0.0.0.0/0'
  protocol :tcp
  command :allow
end

if opt_enable_ipv6
  firewall_rule 'socks5_ipv6' do
    port 1080
    source '::/0'
    protocol :tcp
    command :allow
  end
end

node['private']['vpn'].each do |server_name, server_data|
  vpn_server server_name do
    fqdn server_data['fqdn']
    user instance.user
    group instance.group
    certificate JSON.parse(server_data['certificate'].to_json, symbolize_names: true)
    port server_data['port']
    network server_data['network']
    openvpn JSON.parse(server_data['openvpn'].to_json, symbolize_names: true)
    manage_firewall_rules server_data.fetch('manage_firewall_rules', false)
    redirect_gateway server_data.fetch('redirect_gateway', false)
    bypass_dhcp server_data.fetch('bypass_dhcp', true)
    bypass_dns server_data.fetch('bypass_dns', true)
    action :setup
  end

  server_data['clients'].each do |client_name, client_data|
    vpn_client "#{client_name}@#{server_name}" do
      name client_name
      user instance.user
      group instance.group
      server server_name
      ipv4_address client_data['ipv4_address']
      action :create
    end
  end
end

ngx_http_ssl_module 'default' do
  openssl_version node['openssl']['version']
  openssl_checksum node['openssl']['checksum']
  action :add
end

ngx_http_v2_module 'default'
ngx_http_stub_status_module 'default'

dhparam_file 'default' do
  key_length 2048
  action :create
end

opt_enable_ipv6 = node['firewall']['ipv6_enabled']

nginx_install 'default' do
  version node['nginx']['version']
  checksum node['nginx']['checksum']
  with_ipv6 opt_enable_ipv6
  with_threads false
  with_debug false
  directives(
    main: {
      worker_processes: 'auto'
    },
    events: {
      worker_connections: 1024,
      multi_accept: 'on'
    },
    http: {
      server_tokens: 'off',
      sendfile: 'on',
      tcp_nopush: 'on',
      tcp_nodelay: 'on',
      keepalive_requests: 250,
      keepalive_timeout: 100
    }
  )
  action :run
end

nginx_conf 'gzip' do
  cookbook 'private'
  template 'nginx/gzip.conf.erb'
  action :create
end

nginx_conf 'resolver' do
  cookbook 'private'
  template 'nginx/resolver.conf.erb'
  variables(
    resolvers: %w[1.1.1.1 8.8.8.8 1.0.0.1 8.8.4.4],
    resolver_valid: 600,
    resolver_timeout: 10
  )
  action :create
end

stub_status_host = '127.0.0.1'
stub_status_port = 8099

nginx_vhost 'stub_status' do
  cookbook 'private'
  template 'nginx/stub_status.vhost.erb'
  variables(
    host: stub_status_host,
    port: stub_status_port
  )
  action :enable
end

nginx_conf 'ssl' do
  cookbook 'ngx-modules'
  template 'ssl.conf.erb'
  variables(lazy {
    {
      ssl_dhparam: ::ChefCookbook::DHParam.file(node, 'default'),
      ssl_configuration: 'modern'
    }
  })
  action :create
end

logrotate_app 'nginx' do
  path(lazy { ::File.join(node.run_state['nginx']['log_dir'], '*.log') })
  frequency 'daily'
  rotate 30
  options %w[
    missingok
    compress
    delaycompress
    notifempty
  ]
  postrotate(lazy { "[ ! -f #{node.run_state['nginx']['pid']} ] || kill -USR1 `cat #{node.run_state['nginx']['pid']}`" })
  action :enable
end

firewall_rule 'http' do
  port 80
  source '0.0.0.0/0'
  protocol :tcp
  command :allow
end

firewall_rule 'https' do
  port 443
  source '0.0.0.0/0'
  protocol :tcp
  command :allow
end

if opt_enable_ipv6
  firewall_rule 'http_ipv6' do
    port 80
    source '::/0'
    protocol :tcp
    command :allow
  end

  firewall_rule 'https_ipv6' do
    port 443
    source '::/0'
    protocol :tcp
    command :allow
  end
end

if node['private']['netdata']['slave']['enabled']
  netdata_install 'default' do
    install_method 'source'
    git_repository node['private']['netdata']['git_repository']
    git_revision node['private']['netdata']['git_revision']
    git_source_directory '/opt/netdata'
    autoupdate false
    update false
  end

  netdata_config 'global' do
    owner 'netdata'
    group 'netdata'
    configurations(
      'memory mode' => 'none'
    )
  end

  netdata_stream 'stream' do
    owner 'netdata'
    group 'netdata'
    configurations(
      'enabled' => 'yes',
      'destination' => node['private']['netdata']['slave']['stream']['destination'],
      'api key' => secret.get("netdata:stream:api_key:#{node['private']['netdata']['slave']['stream']['name']}", required: node['private']['netdata']['slave']['enabled'], prefix_fqdn: false)
    )
  end

  netdata_python_plugin 'nginx' do
    owner 'netdata'
    group 'netdata'
    global_configuration(
      'retries' => 1,
      'update_every' => 1
    )
    jobs(
      'local' => {
        'url' => "http://#{stub_status_host}:#{stub_status_port}/stub_status"
      }
    )
  end
end

volgactf_qualifier_proxy_opts = opt.fetch('volgactf', {}).fetch('qualifier', '').fetch('proxy', nil)
unless volgactf_qualifier_proxy_opts.nil?
  volgactf_qualifier_proxy volgactf_qualifier_proxy_opts['fqdn'] do
    ipv4_address volgactf_qualifier_proxy_opts['ipv4_address']
    secure volgactf_qualifier_proxy_opts.fetch('secure', true)
    hsts_max_age volgactf_qualifier_proxy_opts.fetch('hsts_max_age', 15_768_000)
    oscp_stapling volgactf_qualifier_proxy_opts.fetch('oscp_stapling', true)
    resolvers volgactf_qualifier_proxy_opts.fetch('resolvers', %w(8.8.8.8 1.1.1.1 8.8.4.4 1.0.0.1))
    resolver_valid volgactf_qualifier_proxy_opts.fetch('resolver_valid', 600)
    resolver_timeout volgactf_qualifier_proxy_opts.fetch('resolver_timeout', 10)
    access_log_options volgactf_qualifier_proxy_opts.fetch('access_log_options', 'combined')
    error_log_options volgactf_qualifier_proxy_opts.fetch('error_log_options', 'error')
  end
end

require 'json'

apt_update 'update'

build_essential 'install' do
  compile_time true
  action :install
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
  'COMMIT_FILTER' => 100,
  '*nat' => 101,
  ':PREROUTING ACCEPT' => 102,
  ':POSTROUTING ACCEPT' => 103,
  ':OUTPUT ACCEPT_NAT' => 104,
  'COMMIT_NAT' => 200
}

include_recipe 'firewall::default'

include_recipe 'latest-nodejs::default'

ngx_http_ssl_module 'default' do
  openssl_version '1.1.1b'
  openssl_checksum '5c557b023230413dfb0756f3137a13e6d726838ccd1430888ad15bfb2b43ea4b'
  action :add
end

ngx_http_v2_module 'default'

dhparam_file 'default' do
  key_length 2048
  action :create
end

nginx_install 'default' do
  version '1.15.11'
  checksum 'd5eb2685e2ebe8a9d048b07222ffdab50e6ff6245919eebc2482c1f388e3f8ad'
  with_ipv6 true
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
  template 'gzip.nginx.conf.erb'
  action :create
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

instance = ::ChefCookbook::Instance::Helper.new(node)

node_part = node['private']['personal']

private_ruby node_part['ruby_version'] do
  user instance.user
  group instance.group
  user_home instance.user_home
  bundler_version node_part['bundler_version']
  action :install
end

opt_develop = node_part.fetch('develop', false)
opt_enable_ipv6 = node['firewall']['ipv6_enabled']

if opt_develop
  ssh_private_key instance.user
end

personal_website node_part['fqdn'] do
  user instance.user
  group instance.group
  develop opt_develop
  git_config node_part.fetch('git_config', {})
  ruby_version node_part['ruby_version']
  listen_ipv6 opt_enable_ipv6
  access_log_options 'combined'
  error_log_options 'warn'
  action :install
end

redirect_host "www.#{node_part['fqdn']}" do
  target node_part['fqdn']
  listen_ipv6 opt_enable_ipv6
  default_server false
  secure true
  permanent true
  pass_request_uri true
  access_log_options 'combined'
  error_log_options 'warn'
  action :create
end

include_recipe 'sockd::default'

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

firewall_rule 'socks5' do
  port 1080
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
    action :setup
  end

  firewall_rule "openvpn-#{server_name}" do
    port server_data['port']
    source '0.0.0.0/0'
    protocol server_data['openvpn']['proto'].to_sym
    command :allow
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

# volgactf_part = node['private']['volgactf']['qualifier']
# volgactf_qualifier_proxy volgactf_part['fqdn'] do
#   ipv4_address volgactf_part['ipv4_address']
#   secure volgactf_part.fetch('secure', false)
#   oscp_stapling volgactf_part.fetch('oscp_stapling', false)
#   action :create
# end

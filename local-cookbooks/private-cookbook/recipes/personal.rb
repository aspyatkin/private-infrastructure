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

timezone 'UTC' do
  timezone 'Etc/UTC'
  action :set
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

package 'cron'

service 'cron' do
  action [:enable, :start]
end

cronic 'default' do
  action :install
end

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
  users opt['ssmtp'].fetch('users', [])
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

include_recipe 'nodejs::nodejs_from_binary'

ngx_http_ssl_module 'default' do
  openssl_version node['openssl']['version']
  openssl_checksum node['openssl']['checksum']
  action :add
end

ngx_http_v2_module 'default'
ngx_http_stub_status_module 'default'
ngx_http_dav_module 'default'
ngx_http_dav_ext_module 'default'

dhparam_file 'default' do
  key_length 2048
  action :create
end

opt_enable_ipv6 = node['firewall']['ipv6_enabled']

nginx_install 'default' do
  version node['ngx']['version']
  checksum node['ngx']['checksum']
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

instance = ::ChefCookbook::Instance::Helper.new(node)
secret = ::ChefCookbook::Secret::Helper.new(node)

node_part = node['private']['personal']

private_ruby node_part['ruby_version'] do
  user instance.user
  group instance.group
  user_home instance.user_home
  bundler_version node_part['bundler_version']
  action :install
end

opt_develop = node_part.fetch('develop', false)

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

webdav_root_dir = '/etc/chef-webdav'

opt['webdav']['directories'].each do |descriptor|
  private_webdav_directory descriptor do
    credentials secret.get("webdav:directories:#{descriptor}:credentials")
    root_dir opt['webdav']['root_dir']
    action :create
  end
end

private_sec_archive_dir 'webdav-backup' do
  archive_dir opt['webdav']['root_dir']
  environment secret.get('webdav:backup:environment', default: {})
  public_key secret.get('webdav:backup:public_key')
  cron opt['webdav']['backup']['cron']
  action :setup
end

webdav_fqdn = opt['webdav']['fqdn']

webdav_vhost_vars = {
  fqdn: webdav_fqdn,
  listen_ipv6: true,
  default_server: false,
  access_log_options: 'off',
  error_log_options: 'error',
  hsts_max_age: 15_768_000,
  oscp_stapling: true,
  resolvers: %w(8.8.8.8 1.1.1.1 8.8.4.4 1.0.0.1),
  resolver_valid: 600,
  resolver_timeout: 10,
  certificate_entries: []
}

tls_rsa_certificate webdav_fqdn do
  action :deploy
end

tls = ::ChefCookbook::TLS.new(node)
webdav_vhost_vars[:certificate_entries] << tls.rsa_certificate_entry(webdav_fqdn)

if tls.has_ec_certificate?(webdav_fqdn)
  tls_ec_certificate webdav_fqdn do
    action :deploy
  end

  webdav_vhost_vars[:certificate_entries] << tls.ec_certificate_entry(webdav_fqdn)
end

nginx_vhost webdav_fqdn do
  cookbook 'private'
  template 'nginx/webdav.vhost.conf.erb'
  variables(lazy {
    webdav_vhost_vars.merge(
      access_log: ::File.join(node.run_state['nginx']['log_dir'], "#{webdav_fqdn}_access.log"),
      error_log: ::File.join(node.run_state['nginx']['log_dir'], "#{webdav_fqdn}_error.log"),
      locations: opt['webdav']['directories'].map { |x| [x, ::ChefCookbook::NgxHelper.include_path("chef-webdav-#{x}")] }.to_h
    )
  })
  action :enable
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

opt['vpn'].each do |server_name, server_data|
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

if opt['netdata']['slave']['enabled']
  netdata_install 'default' do
    install_method 'source'
    git_repository opt['netdata']['git_repository']
    git_revision opt['netdata']['git_revision']
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
      'destination' => opt['netdata']['slave']['stream']['destination'],
      'api key' => secret.get("netdata:stream:api_key:#{opt['netdata']['slave']['stream']['name']}", required: opt['netdata']['slave']['enabled'], prefix_fqdn: false)
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

private_acme 'acme' do
  group 'acme'
  account_email 'acme@srvr.work'
  environment secret.get('acme:environment', default: {})
  cron opt['acme']['cron']
  backup_environment secret.get('acme:backup:environment', default: {})
  backup_public_key secret.get('acme:backup:public_key')
  backup_cron opt['acme']['backup']['cron']
  action :setup
end

# volgactf_qualifier = node['private']['volgactf']['qualifier']
# volgactf_qualifier_proxy volgactf_qualifier['fqdn'] do
#   ipv4_address volgactf_qualifier['ipv4_address']
#   secure volgactf_qualifier.fetch('secure', false)
#   oscp_stapling volgactf_qualifier.fetch('oscp_stapling', false)
#   action :create
# end

# volgactf_final = node['private']['volgactf']['final']
# volgactf_final_proxy volgactf_final['fqdn'] do
#   ipv4_address volgactf_final['ipv4_address']
#   secure volgactf_final.fetch('secure', false)
#   oscp_stapling volgactf_final.fetch('oscp_stapling', false)
#   action :create
# end

# ctf_moscow_2019_101_website node['private']['ctf-moscow-2019-101']['fqdn'] do
#   user instance.user
#   group instance.group
#   revision node['private']['ctf-moscow-2019-101']['revision']
#   listen_ipv6 opt_enable_ipv6
#   access_log_options 'combined'
#   error_log_options 'warn'
#   action :install
# end

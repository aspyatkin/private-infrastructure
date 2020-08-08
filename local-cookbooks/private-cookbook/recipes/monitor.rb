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
  ':FORWARD DROP' => 3,
  ':OUTPUT ACCEPT_FILTER' => 4,
  '-N fail2ban' => 45,
  '-A fail2ban -j RETURN' => 45,
  '-A INPUT -j fail2ban' => 45,
  'COMMIT_FILTER' => 100,
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

ngx_http_ssl_module 'default' do
  openssl_version '1.1.1d'
  openssl_checksum '1e3a91bc1f9dfce01af26026f856e064eab4c8ee0a8f457b5ae30b40b8b711f2'
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
  version '1.17.7'
  checksum 'b62756842807e5693b794e5d0ae289bd8ae5b098e66538b2a91eb80f25c591ff'
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
    'bind to' => opt['netdata']['master']['listen']['host'],
    'default port' => opt['netdata']['master']['listen']['port'],
    'memory mode' => 'ram',
    'history' => opt['netdata']['master']['history']
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

service 'netdata' do
  action :nothing
end

secret = ::ChefCookbook::Secret::Helper.new(node)

template '/etc/netdata/health_alarm_notify.conf' do
  source 'netdata/health_alarm_notify.conf.erb'
  owner 'netdata'
  group 'netdata'
  mode 0o644
  variables(
    telegram_enabled: opt['monitor']['netdata']['health']['telegram']['enabled'],
    telegram_bot_token: secret.get('telegram:bot_token', required: opt['monitor']['netdata']['health']['telegram']['enabled'], default: nil),
    telegram_recipients: opt['monitor']['netdata']['health']['telegram']['recipients']
  )
  action :create
  notifies :restart, 'service[netdata]', :delayed
end

opt['netdata']['master']['stream'].each do |stream_name, stream_data|
  netdata_stream stream_name do
    config_name secret.get("netdata:stream:api_key:#{stream_name}", prefix_fqdn: false)
    owner 'netdata'
    group 'netdata'
    configurations(
      'enabled' => 'yes',
      'default history' => stream_data.fetch('history', 3600),
      'default memory mode' => 'ram',
      'health enabled by default' => 'auto',
      'allow from' => stream_data['origin']
    )
  end
end

htpasswd_dir = '/opt/netdata_master'

directory htpasswd_dir do
  owner(lazy { node.run_state['nginx']['user'] })
  group(lazy { node.run_state['nginx']['group'] })
  recursive true
  mode 0o700
  action :create
end

htpasswd_file = ::File.join(htpasswd_dir, 'htpasswd')

secret.get('netdata:basic-auth', prefix_fqdn: false).each do |username, pwd|
  htpasswd "#{username}@#{htpasswd_file}" do
    file htpasswd_file
    user username
    password pwd
    action :add
  end
end

ngx_vars = {
  fqdn: opt['monitor']['netdata']['fqdn'],
  listen_ipv6: opt_enable_ipv6,
  default_server: opt['monitor']['netdata']['default_server'],
  access_log_options: opt['monitor']['netdata']['access_log_options'],
  error_log_options: opt['monitor']['netdata']['error_log_options'],
  upstream_host: '127.0.0.1',
  upstream_port: opt['netdata']['master']['listen']['port'],
  upstream_keepalive: 64,
  netdata_htpasswd: htpasswd_file
}

tls_rsa_certificate opt['monitor']['netdata']['fqdn'] do
  action :deploy
end

tls = ::ChefCookbook::TLS.new(node)

ngx_vars.merge!(
  certificate_entries: [
    tls.rsa_certificate_entry(opt['monitor']['netdata']['fqdn'])
  ],
  hsts_max_age: opt['monitor']['netdata']['hsts_max_age'],
  oscp_stapling: opt['monitor']['netdata']['oscp_stapling']
)

if tls.has_ec_certificate?(opt['monitor']['netdata']['fqdn'])
  tls_ec_certificate opt['monitor']['netdata']['fqdn'] do
    action :deploy
  end

  ngx_vars[:certificate_entries] <<
    tls.ec_certificate_entry(opt['monitor']['netdata']['fqdn'])
end

nginx_vhost 'netdata' do
  cookbook 'private'
  template 'netdata/nginx.vhost.erb'
  variables(lazy {
    ngx_vars.merge(
      access_log: ::File.join(
        node.run_state['nginx']['log_dir'],
        'netdata-access.log'
      ),
      error_log: ::File.join(
        node.run_state['nginx']['log_dir'],
        'netdata-error.log'
      )
    )
  })
  action :enable
end

opt['netdata']['master']['stream'].each do |_, stream_data|
  source_from = "#{stream_data['origin']}/32"
  firewall_rule "allow netdata access from #{source_from}" do
    port opt['netdata']['master']['listen']['port']
    source source_from
    protocol :tcp
    command :allow
  end
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

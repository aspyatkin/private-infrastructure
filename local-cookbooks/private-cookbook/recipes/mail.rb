# repos
apt_update 'default' do
  action :update
  notifies :install, 'build_essential[default]', :immediately
end

build_essential 'default' do
  action :nothing
end
# end repos

# locale
locale 'en' do
  lang 'en_US.utf8'
  lc_all 'en_US.utf8'
  action :update
end
# end locale

# ntp
include_recipe 'ntp::default'
# end ntp

# firewall
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
# end firewall

opt = node['private']
secret = ::ChefCookbook::Secret::Helper.new(node)

# ssmtp
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
# end ssmtp

# fail2ban
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
# end fail2ban

# dnsmasq
private_dns 'default' do
  listen_address '127.0.0.1'
  bind_interfaces true
  action :install
end
# end dnsmasq

# nginx
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
# end nginx

# vmail
opt_vmail = opt['mail']['vmail']

group opt_vmail['group'] do
  gid opt_vmail['gid']
  action :create
end

user opt_vmail['user'] do
  uid opt_vmail['uid']
  group opt_vmail['group']
  shell '/bin/false'
  manage_home true
  home opt_vmail['home']
  action :create
end

directory opt_vmail['trash'] do
  owner opt_vmail['user']
  group opt_vmail['group']
  mode 0755
  action :create
end
# end vmail

# postgres server
opt_postgres = opt['mail']['postgres']

postgresql_server_install 'PostgreSQL Server' do
  setup_repo true
  version opt_postgres['version']
  password secret.get('postgres:password:postgres')
  action %i[install create]
end

service 'postgresql' do
  action :nothing
end

postgres_service_resource = 'service[postgresql]'

postgresql_server_conf 'PostgreSQL Config' do
  version opt_postgres['version']
  port opt_postgres['port']
  additional_config 'listen_addresses' => '127.0.0.1'
  action :modify
  notifies :reload, postgres_service_resource, :delayed
end
# end postgres server

# postgres databases
opt_postfixadmin_db = opt['mail']['postfixadmin']['database']

postgresql_user opt_postfixadmin_db['user'] do
  password secret.get("postgres:password:#{opt_postfixadmin_db['user']}")
  action :create
end

postgresql_database opt_postfixadmin_db['name'] do
  locale opt_postfixadmin_db['locale']
  owner opt_postfixadmin_db['user']
  action :create
end
# end postgres databases

# php
include_recipe 'php::default'

# %w(
#   curl
#   gd
#   pgsql
#   imap
#   intl
# )

%w(
  php-pgsql
  php-mbstring
  php-imap
).each do |package_name|
  package package_name do
    action :install
  end
end

# execute 'Enable PHP imap' do
#   command 'php5enmod imap'
#   user 'root'
#   group node['root_group']
#   action :run
# end
# end php

# postfixadmin
opt_postfixadmin = opt['mail']['postfixadmin']

group opt_postfixadmin['group'] do
  system true
  action :create
end

user opt_postfixadmin['user'] do
  group opt_postfixadmin['group']
  shell '/bin/false'
  system true
  action :create
end

ark 'postfixadmin' do
  url opt_postfixadmin['url'] % { version: opt_postfixadmin['version'] }
  version opt_postfixadmin['version']
  checksum opt_postfixadmin['checksum']
  owner opt_postfixadmin['user']
  group opt_postfixadmin['group']
  action :install
end

postfixadmin_templates_dir = ::File.join(
  node['ark']['prefix_root'],
  'postfixadmin',
  'templates_c'
)

directory postfixadmin_templates_dir do
  owner opt_postfixadmin['user']
  group opt_postfixadmin['group']
  recursive false
  mode 0o700
  action :create
end

postfixadmin_mailbox_postdeletion_script = '/usr/local/bin/postfixadmin-mailbox-postdeletion'

# template mailbox_postdeletion_path do
#   source 'postfixadmin/mailbox-postdeletion.sh.erb'
#   owner 'root'
#   group node['root_group']
#   mode 0755
#   variables(
#     basedir: node[id]['vmail']['home'],
#     trashbase: node[id]['vmail']['trashbase'],
#     db_host: node[id]['postgres']['host'],
#     db_port: node[id]['postgres']['port'],
#     db_user: node[id]['roundcube']['database']['user'],
#     db_password: helper.postgres_user_password(
#       node[id]['roundcube']['database']['user']
#     ),
#     db_name: node[id]['roundcube']['database']['name']
#   )
#   action :create
# end

postfixadmin_domain_postdeletion_script = '/usr/local/bin/postfixadmin-domain-postdeletion'

# template domain_postdeletion_path do
#   source 'postfixadmin/domain-postdeletion.sh.erb'
#   owner 'root'
#   group node['root_group']
#   mode 0755
#   variables(
#     basedir: node[id]['vmail']['home'],
#     trashbase: node[id]['vmail']['trashbase'],
#     db_host: node[id]['postgres']['host'],
#     db_port: node[id]['postgres']['port'],
#     db_user: node[id]['roundcube']['database']['user'],
#     db_password: helper.postgres_user_password(
#       node[id]['roundcube']['database']['user']
#     ),
#     db_name: node[id]['roundcube']['database']['name']
#   )
#   action :create
# end

file '/etc/sudoers.d/postfixadmin' do
  owner 'root'
  group node['root_group']
  content "#{opt_postfixadmin['user']} ALL=("\
          "#{opt_vmail['user']}) NOPASSWD: "\
          "#{postfixadmin_mailbox_postdeletion_script}, "\
          "#{postfixadmin_domain_postdeletion_script}\n"
  mode 0440
  action :create
end

postfixadmin_helper = ::ChefCookbook::Private::PostfixadminHelper.new(node)

template 'postfixadmin configuration' do
  path "#{node['ark']['prefix_root']}/postfixadmin/config.local.php"
  source 'postfixadmin/config.local.php.erb'
  owner opt_postfixadmin['user']
  group opt_postfixadmin['group']
  mode 0640
  variables(
    database_type: 'pgsql',
    database_host: '127.0.0.1',
    database_port: opt_postgres['port'],
    database_user: opt_postfixadmin_db['user'],
    database_password: secret.get("postgres:password:#{opt_postfixadmin_db['user']}"),
    database_name: opt_postfixadmin_db['name'],
    setup_password: postfixadmin_helper.setup_password,
    aliases: 10,
    mailboxes: 10,
    maxquota: 200,
    domain_quota_default: 2048,
    quota_multiplier: 1048576,
    vmail_user: opt_vmail['user'],
    mailbox_postdeletion_script: postfixadmin_mailbox_postdeletion_script,
    domain_postdeletion_script: postfixadmin_domain_postdeletion_script
  )
end

php_fpm_pool 'postfixadmin' do
  listen opt_postfixadmin['php_fpm_pool']['listen']
  user opt_postfixadmin['user']
  group opt_postfixadmin['group']
  process_manager 'dynamic'
  max_children opt_postfixadmin['php_fpm_pool']['max_children']
  start_servers opt_postfixadmin['php_fpm_pool']['start_servers']
  min_spare_servers \
    opt_postfixadmin['php_fpm_pool']['min_spare_servers']
  max_spare_servers \
    opt_postfixadmin['php_fpm_pool']['max_spare_servers']
  additional_config(
    'pm.max_requests' => opt_postfixadmin['php_fpm_pool']['max_requests'],
    'listen.mode' => '0666',
    'php_admin_flag[log_errors]' => 'on',
    'php_value[date.timezone]' => 'UTC',
    'php_value[expose_php]' => 'off',
    'php_value[display_errors]' => 'off',
    'php_value[memory_limit]' => opt_postfixadmin['php_fpm_pool']['memory_limit']
  )
end

ngx_vars = {
  fqdn: opt_postfixadmin['fqdn'],
  listen_ipv6: opt_enable_ipv6,
  default_server: opt_postfixadmin['default_server'],
  access_log_options: opt_postfixadmin['access_log_options'],
  error_log_options: opt_postfixadmin['error_log_options'],
  root: "#{node['ark']['prefix_root']}/postfixadmin/public",
  fastcgi_pass: "unix:#{opt_postfixadmin['php_fpm_pool']['listen']}",
  enable_setup_page: opt_postfixadmin['enable_setup_page']
}

tls_rsa_certificate opt_postfixadmin['fqdn'] do
  action :deploy
end

tls = ::ChefCookbook::TLS.new(node)

ngx_vars.merge!(
  certificate_entries: [
    tls.rsa_certificate_entry(opt_postfixadmin['fqdn'])
  ],
  hsts_max_age: opt_postfixadmin['hsts_max_age'],
  oscp_stapling: opt_postfixadmin['oscp_stapling']
)

if tls.has_ec_certificate?(opt_postfixadmin['fqdn'])
  tls_ec_certificate opt_postfixadmin['fqdn'] do
    action :deploy
  end

  ngx_vars[:certificate_entries] <<
    tls.ec_certificate_entry(opt_postfixadmin['fqdn'])
end

nginx_vhost 'postfixadmin' do
  cookbook 'private'
  template 'postfixadmin/nginx.vhost.erb'
  variables(lazy {
    ngx_vars.merge(
      access_log: ::File.join(
        node.run_state['nginx']['log_dir'],
        'postfixadmin-access.log'
      ),
      error_log: ::File.join(
        node.run_state['nginx']['log_dir'],
        'postfixadmin-error.log'
      )
    )
  })
  action :enable
end
# end postfixadmin

# postfix
%w(sendmail).each do |package_name|
  package package_name do
    action :remove
  end
end

%w(postfix postfix-pgsql).each do |package_name|
  package package_name do
    action :install
  end
end

service 'postfix' do
  action [:enable, :start]
end

opt_postfix = opt['mail']['postfix']
opt_postfix_db = opt['mail']['postfix']['database']

postgresql_user opt_postfix_db['user'] do
  password secret.get("postgres:password:#{opt_postfix_db['user']}")
  action :create
end

postfix_dir = '/etc/postfix'

postfix_grant_access_script = ::File.join(postfix_dir, 'postgres_grant_access.sql')

template postfix_grant_access_script do
  source 'postfix/postgres_grant_access.sql.erb'
  owner 'root'
  group node['root_group']
  mode 0640
  variables(
    user: opt_postfix_db['user']
  )
end

execute 'grant access to postfixadmin tables' do
  command "psql -h 127.0.0.1 -p #{opt_postgres['port']} -U postgres -d #{opt_postfixadmin_db['name']} -f #{postfix_grant_access_script}"
  user 'root'
  group node['root_group']
  environment(
    'PGPASSWORD' => secret.get('postgres:password:postgres')
  )
  action :run
end

postfix_map_variables = {
  user: opt_postfix_db['user'],
  password: secret.get("postgres:password:#{opt_postfix_db['user']}"),
  host: '127.0.0.1',
  port: opt_postgres['port'],
  dbname: opt_postfixadmin_db['name']
}

postfix_virtual_alias_maps = []


postgres_virtual_alias_maps = ::File.join(postfix_dir, 'postgres_virtual_alias_maps.cf')

template postgres_virtual_alias_maps do
  source 'postfix/postgres_virtual_alias_maps.cf.erb'
  owner 'root'
  group node['root_group']
  mode 0640
  variables postfix_map_variables
  action :create
  notifies :reload, 'service[postfix]', :delayed
end

postfix_virtual_alias_maps << "proxy:pgsql:#{postgres_virtual_alias_maps}"


postgres_virtual_alias_domain_maps = ::File.join(postfix_dir, 'postgres_virtual_alias_domain_maps.cf')

template postgres_virtual_alias_domain_maps do
  source 'postfix/postgres_virtual_alias_domain_maps.cf.erb'
  owner 'root'
  group node['root_group']
  mode 0640
  variables postfix_map_variables
  action :create
  notifies :reload, 'service[postfix]', :delayed
end

postfix_virtual_alias_maps << "proxy:pgsql:#{postgres_virtual_alias_domain_maps}"


postgres_virtual_alias_domain_catchall_maps = ::File.join(postfix_dir, 'postgres_virtual_alias_domain_catchall_maps.cf')

template postgres_virtual_alias_domain_catchall_maps do
  source 'postfix/postgres_virtual_alias_domain_catchall_maps.cf.erb'
  owner 'root'
  group node['root_group']
  mode 0640
  variables postfix_map_variables
  action :create
  notifies :reload, 'service[postfix]', :delayed
end

postfix_virtual_alias_maps << "proxy:pgsql:#{postgres_virtual_alias_domain_catchall_maps}"


postfix_virtual_mailbox_domains = []

postgres_virtual_domain_maps = ::File.join(postfix_dir, 'postgres_virtual_domain_maps.cf')

template postgres_virtual_domain_maps do
  source 'postfix/postgres_virtual_domain_maps.cf.erb'
  owner 'root'
  group node['root_group']
  mode 0640
  variables postfix_map_variables
  action :create
  notifies :reload, 'service[postfix]', :delayed
end

postfix_virtual_mailbox_domains << "proxy:pgsql:#{postgres_virtual_domain_maps}"


postfix_virtual_mailbox_maps = []

postgres_virtual_mailbox_maps = ::File.join(postfix_dir, 'postgres_virtual_mailbox_maps.cf')

template postgres_virtual_mailbox_maps do
  source 'postfix/postgres_virtual_mailbox_maps.cf.erb'
  owner 'root'
  group node['root_group']
  mode 0640
  variables postfix_map_variables
  action :create
  notifies :reload, 'service[postfix]', :delayed
end

postfix_virtual_mailbox_maps << "proxy:pgsql:#{postgres_virtual_mailbox_maps}"

postgres_virtual_alias_domain_mailbox_maps = ::File.join(postfix_dir, 'postgres_virtual_alias_domain_mailbox_maps.cf')

template postgres_virtual_alias_domain_mailbox_maps do
  source 'postfix/postgres_virtual_alias_domain_mailbox_maps.cf.erb'
  owner 'root'
  group node['root_group']
  mode 0640
  variables postfix_map_variables
  action :create
  notifies :reload, 'service[postfix]', :delayed
end

postfix_virtual_mailbox_maps << "proxy:pgsql:#{postgres_virtual_alias_domain_mailbox_maps}"


postgres_virtual_mailbox_limit_maps = ::File.join(postfix_dir, 'postgres_virtual_mailbox_limit_maps.cf')

template postgres_virtual_mailbox_limit_maps do
  source 'postfix/postgres_virtual_mailbox_limit_maps.cf.erb'
  owner 'root'
  group node['root_group']
  mode 0640
  variables postfix_map_variables
  action :create
  notifies :reload, 'service[postfix]', :delayed
end


postfix_main = ::File.join(postfix_dir, 'main.cf')

template postfix_main do
  source 'postfix/main.cf.erb'
  owner 'root'
  group node['root_group']
  mode 0644
  variables(
    fqdn: opt_postfix['fqdn']
  )
  action :create
  notifies :reload, 'service[postfix]', :delayed
end


postfix_master = ::File.join(postfix_dir, 'master.cf')

template postfix_master do
  source 'postfix/master.cf.erb'
  owner 'root'
  group node['root_group']
  mode 0644
  variables(
  )
  action :create
  notifies :reload, 'service[postfix]', :delayed
end


# end postfix

# netdata
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

  package 'python-psycopg2'

  netdata_python_plugin 'postgres' do
    owner 'netdata'
    group 'netdata'
    global_configuration(
      'retries' => 5,
      'update_every' => 1
    )
    jobs(
      'local' => {
        'host' => '127.0.0.1',
        'port' => opt_postgres['port'],
        'user' => 'postgres',
        'password' => secret.get('postgres:password:postgres')
      }
    )
  end
end
# end netdata

# firewall rules
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
# end firewall rules

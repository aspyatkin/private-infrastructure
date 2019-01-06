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
include_recipe 'firewall::default'
include_recipe 'latest-nodejs::default'
include_recipe 'dhparam::default_key'
include_recipe 'ngx::default'
include_recipe 'nginx-amplify::default' if node.chef_environment.start_with?('production')

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

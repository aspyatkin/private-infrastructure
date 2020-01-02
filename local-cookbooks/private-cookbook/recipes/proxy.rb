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

if node['private']['netdata']['slave']['enabled']
  netdata_install 'default' do
    install_method 'source'
    git_repository node['private']['netdata']['git_repository']
    git_revision node['private']['netdata']['git_revision']
    git_source_directory '/opt/netdata'
    autoupdate true
    update true
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
end

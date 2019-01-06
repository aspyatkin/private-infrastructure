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

node_part = node['private']['nsd']
instance = ::ChefCookbook::Instance::Helper.new(node)
slave_part = node_part['slaves'][instance.fqdn]
secret = ::ChefCookbook::Secret::Helper.new(node)

opt_port = slave_part.fetch('port', 53)
opt_enable_ipv6 = node_part.fetch('enable_ipv6', false)

nsd_slave instance.fqdn do
  port opt_port
  bind_addresses slave_part['bind_addresses']
  enable_ipv6 opt_enable_ipv6
  key secret.get("nsd:keys:#{instance.fqdn}", prefix_fqdn: false)
  zones node_part['zones']
  master_ipv4_address node_part['master']['ipv4_address']
  action :install
end

protocols = %w(tcp udp)

protocols.each do |proto|
  firewall_rule "nsd_#{proto}_ipv4" do
    port opt_port
    source '0.0.0.0/0'
    protocol proto.to_sym
    command :allow
  end
end

if opt_enable_ipv6
  protocols.each do |proto|
    firewall_rule "nsd_#{proto}_ipv6" do
      port opt_port
      source '::/0'
      protocol proto.to_sym
      command :allow
    end
  end
end

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
secret = ::ChefCookbook::Secret::Helper.new(node)

opt_port = node_part['master'].fetch('port', 53)
opt_enable_ipv6 = node_part.fetch('enable_ipv6', false)

nsd_master node_part['master']['fqdn'] do
  port opt_port
  ipv4_address node_part['master']['ipv4_address']
  ipv6_address node_part['master'].fetch('ipv6_address', nil)
  contact node_part['master']['contact']
  bind_addresses node_part['master']['bind_addresses']
  enable_ipv6 opt_enable_ipv6
  keys secret.get('nsd:keys', default: {}, prefix_fqdn: false)
  slaves node_part['slaves']
  zones node_part['zones']
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

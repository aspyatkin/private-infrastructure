resource_name :private_webdav_directory

property :descriptor, String, name_property: true
property :credentials, Hash, default: {}
property :root_dir, String, default: '/etc/chef-webdav'

action :create do
  directory new_resource.root_dir do
    owner lazy { node.run_state['nginx']['user'] }
    group lazy { node.run_state['nginx']['group'] }
    mode 00755
    action :create
  end

  entry_dir = ::File.join(new_resource.root_dir, new_resource.descriptor)

  directory entry_dir do
    owner lazy { node.run_state['nginx']['user'] }
    group lazy { node.run_state['nginx']['group'] }
    mode 00755
    action :create
  end

  data_dir = ::File.join(entry_dir, 'data')

  directory data_dir do
    owner lazy { node.run_state['nginx']['user'] }
    group lazy { node.run_state['nginx']['group'] }
    mode 00755
    action :create
  end

  htpasswd_file = ::File.join(entry_dir, 'htpasswd')

  new_resource.credentials.each do |username, pwd|
    htpasswd "#{username}@#{htpasswd_file}" do
      file htpasswd_file
      user username
      password pwd
      action :add
    end
  end

  lock_zone_name = "chef-webdav-#{new_resource.descriptor}-locks"

  nginx_conf "chef-webdav-#{new_resource.descriptor}" do
    template 'nginx/chef-webdav-lock-zone.conf.erb'
    variables(
      zone_name: lock_zone_name
    )
    action :create
  end

  nginx_include "chef-webdav-#{new_resource.descriptor}" do
    cookbook 'private'
    template 'nginx/chef-webdav-location.conf.erb'
    variables(
      dir: data_dir,
      zone_name: lock_zone_name,
      htpasswd_file: htpasswd_file
    )
    action :create
  end
end

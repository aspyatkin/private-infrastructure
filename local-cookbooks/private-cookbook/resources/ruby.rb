resource_name :private_ruby

property :version, String, name_property: true

property :user, String, required: true
property :group, String, required: true
property :user_home, String, required: true
property :bundler_version, required: true

default_action :install

action :install do
  rbenv_user_install new_resource.user

  rbenv_plugin 'ruby-build' do
    git_url 'https://github.com/rbenv/ruby-build.git'
    user new_resource.user
  end

  ENV['CONFIGURE_OPTS'] = '--disable-install-rdoc'

  rbenv_ruby new_resource.version do
    user new_resource.user
  end

  rbenv_global new_resource.version do
    user new_resource.user
  end

  rbenv_gem 'bundler' do
    user new_resource.user
    rbenv_version new_resource.version
    version new_resource.bundler_version
  end

  # execute 'Fix permissions on bundle cache dir' do
  #   command "chown -R #{new_resource.user}:#{new_resource.group} #{new_resource.user_home}/.bundle"
  #   action :run
  # end
end

resource_name :private_sec_archive_base

property :notused, name_property: true
property :settings_dir_root, String, required: true

default_action :setup

action :setup do
  package 'python3-pip' do
    action :install
  end

  execute 'pip3 install awscli' do
    action :run
  end

  sec_archive_repo_path = ::File.join(::Chef::Config['file_cache_path'], 'sec-archive')

  git sec_archive_repo_path do
    repository 'https://github.com/aspyatkin/sec-archive'
    revision 'master'
    enable_checkout false
    action :sync
  end

  bash 'install sec-archive' do
    cwd sec_archive_repo_path
    code <<-EOH
      make install
    EOH
    action :run
  end

  directory new_resource.settings_dir_root do
    mode 00700
    action :create
  end
end

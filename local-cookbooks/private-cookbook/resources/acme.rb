resource_name :private_acme

property :user, String, name_property: true
property :group, String, required: true
property :uid, Integer, default: 550
property :gid, Integer, default: 550

property :account_email, String, required: true
property :environment, Hash, default: {}
property :cron, Hash, default: {
  'mailto' => nil,
  'mailfrom' => nil,
  'minute' => '0',
  'hour' => '1',
  'day' => '*',
  'month' => '*',
  'weekday' => '*'
}

property :backup_environment, Hash, default: {}
property :backup_public_key, String, required: true
property :backup_cron, Hash, default: {
  'mailto' => nil,
  'mailfrom' => nil,
  'minute' => '0',
  'hour' => '2',
  'day' => '*',
  'month' => '*',
  'weekday' => '*'
}

default_action :setup

action :setup do
  group new_resource.group do
    gid new_resource.gid
    action :create
  end

  user_home = ::File.join('/home', new_resource.user)

  user new_resource.user do
    uid new_resource.uid
    group new_resource.group
    home user_home
    manage_home true
    action :create
  end

  acme_repo_path = ::File.join(user_home, 'acme.sh')

  git acme_repo_path do
    repository 'https://github.com/acmesh-official/acme.sh.git'
    revision 'master'
    user new_resource.user
    group new_resource.group
    enable_checkout false
    action :sync
  end

  acme_home_path = ::File.join(user_home, '.acme.sh')

  bash "install acme.sh in #{acme_home_path}" do
    cwd acme_repo_path
    code <<-EOH
      ./acme.sh --install --nocron --home #{acme_home_path} --accountemail #{new_resource.account_email}
    EOH
    user new_resource.user
    group new_resource.group
    action :run
    not_if { ::Dir.exist?(acme_home_path) }
  end

  acme_conf_file = ::File.join(acme_home_path, 'account.conf')

  new_resource.environment.each do |key, val|
    replace_or_add "adjust #{key} in #{acme_conf_file}" do
      path acme_conf_file
      pattern ::Regexp.new("^#{key}=.+$")
      line "#{key}='#{val}'"
      ignore_missing false
      action :edit
    end
  end

  cron_cmd = nil

  ruby_block 'acme_cron_cmd' do
    block do
      cronic_installed = !node.run_state['cronic'].nil? && node.run_state['cronic']['installed']
      cron_cmd = "#{cronic_installed ? "#{node.run_state['cronic']['command']} " : ''}#{acme_home_path}/acme.sh --cron --home #{acme_home_path}"
      ssmtp_helper = nil
      if !node.run_state['ssmtp'].nil? && node.run_state['ssmtp']['installed']
        ssmtp_helper = ::ChefCookbook::SSMTP::Helper.new(node)
      end

      unless ssmtp_helper.nil? || new_resource.cron.fetch('mailto', nil).nil? || new_resource.cron.fetch('mailfrom', nil).nil?
        cron_cmd += " 2>&1 | #{ssmtp_helper.mail_send_command('Cron acme', new_resource.cron['mailfrom'], new_resource.cron['mailto'], cronic_installed)}"
      end
    end
    action :run
  end

  cron 'acme' do
    command lazy { cron_cmd }
    path ENV['PATH']
    user new_resource.user
    home user_home
    minute new_resource.cron.fetch('minute', '0')
    hour new_resource.cron.fetch('hour', '1')
    day new_resource.cron.fetch('day', '*')
    month new_resource.cron.fetch('month', '*')
    weekday new_resource.cron.fetch('weekday', '*')
    action :create
  end

  package 'python3-cryptography' do
    action :install
  end

  acme_serialize_repo_path = ::File.join(user_home, 'acme-serialize')

  git acme_serialize_repo_path do
    repository 'https://github.com/aspyatkin/acme-serialize'
    revision 'master'
    user new_resource.user
    group new_resource.group
    enable_checkout false
    action :sync
  end

  acme_serialize_script = '/usr/local/bin/acme-serialize'

  bash 'install acme-serialize' do
    cwd acme_serialize_repo_path
    code <<-EOH
      make install
    EOH
    action :run
  end

  private_sec_archive_dir 'acme-backup' do
    archive_dir acme_home_path
    environment new_resource.backup_environment
    public_key new_resource.backup_public_key
    cron new_resource.backup_cron
    action :setup
  end
end

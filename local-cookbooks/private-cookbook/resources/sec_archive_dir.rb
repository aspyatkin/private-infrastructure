resource_name :private_sec_archive_dir

property :job_name, String, name_property: true
property :archive_dir, String, required: true
property :environment, Hash, default: {}
property :public_key, String, required: true
property :cron, Hash, default: {
  'mailto' => nil,
  'mailfrom' => nil,
  'minute' => '0',
  'hour' => '2',
  'day' => '*',
  'month' => '*',
  'weekday' => '*'
}
property :settings_dir_root, String, default: '/etc/chef-sec-archive'

default_action :setup

action :setup do
  private_sec_archive_base 'default' do
    settings_dir_root new_resource.settings_dir_root
  end

  settings_dir = ::File.join(new_resource.settings_dir_root, new_resource.job_name)

  directory settings_dir do
    mode 00700
    action :create
  end

  env_file = ::File.join(settings_dir, '.env')

  file env_file do
    content new_resource.environment.map { |key, val| "#{key}=#{val}" }.join("\n")
    mode 00600
    sensitive true
    action :create
  end

  public_key = ::File.join(settings_dir, 'key.pub')

  file public_key do
    content new_resource.public_key
    mode 00600
    sensitive true
    action :create
  end

  cron_cmd = nil

  ruby_block "#{new_resource.job_name} cron_cmd" do
    block do
      sec_archive_script = '/usr/local/bin/sec-archive'
      cronic_installed = !node.run_state['cronic'].nil? && node.run_state['cronic']['installed']
      cron_cmd = "#{cronic_installed ? "#{node.run_state['cronic']['command']} " : ''}#{sec_archive_script} #{new_resource.archive_dir} #{settings_dir}"
      ssmtp_helper = nil
      if !node.run_state['ssmtp'].nil? && node.run_state['ssmtp']['installed']
        ssmtp_helper = ::ChefCookbook::SSMTP::Helper.new(node)
      end

      unless ssmtp_helper.nil? || new_resource.cron.fetch('mailto', nil).nil? || new_resource.cron.fetch('mailfrom', nil).nil?
        cron_cmd += " 2>&1 | #{ssmtp_helper.mail_send_command("Cron #{new_resource.job_name}", new_resource.cron['mailfrom'], new_resource.cron['mailto'], cronic_installed)}"
      end
    end
    action :run
  end

  cron new_resource.job_name do
    command lazy { cron_cmd }
    path ENV['PATH']
    minute new_resource.cron.fetch('minute', '0')
    hour new_resource.cron.fetch('hour', '2')
    day new_resource.cron.fetch('day', '*')
    month new_resource.cron.fetch('month', '*')
    weekday new_resource.cron.fetch('weekday', '*')
    action :create
  end
end

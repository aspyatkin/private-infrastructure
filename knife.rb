require 'dotenv'
Dotenv.load

local_mode true
chef_repo_path __dir__

knife[:ssh_attribute] = 'knife_zero.host'
knife[:use_sudo] = true

knife[:automatic_attribute_whitelist] = %w[
  fqdn
  platform
  platform_version
]
knife[:default_attribute_whitelist] = []
knife[:normal_attribute_whitelist] = %w[
  knife_zero
]
knife[:override_attribute_whitelist] = %w[
]

berkshelf_vendor_cmd = 'bundle exec berks vendor cookbooks'

knife[:before_bootstrap] = berkshelf_vendor_cmd
knife[:before_converge]  = berkshelf_vendor_cmd

environment = ::ENV['KNIFE_NODE_ENVIRONMENT'] || ::ENV.fetch('KNIFE_NODE_DEFAULT_ENVIRONMENT', nil)

if environment.nil?
  raise 'Unspecified default environment!'
end

secret_file = ::ENV.fetch("KNIFE_NODE_SECRET_FILE_#{environment.upcase}", nil)
ignore_secret_file = ::ENV.fetch("KNIFE_NODE_IGNORE_SECRET_FILE_#{environment.upcase}", 'no') == 'yes'

unless ignore_secret_file
  secret_file = ::File.expand_path(secret_file)
  if !secret_file.nil? && File.exist?(secret_file)
    knife[:secret_file] = secret_file
  else
    raise 'Couldn\'t find any encrypted data bag secret for environment'\
          " <#{environment}>!"
  end
end

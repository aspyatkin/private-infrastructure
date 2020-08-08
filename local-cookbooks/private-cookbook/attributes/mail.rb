# vmail
default['private']['mail']['vmail']['uid'] = 5000
default['private']['mail']['vmail']['gid'] = 5000
default['private']['mail']['vmail']['user'] = 'vmail'
default['private']['mail']['vmail']['group'] = 'vmail'
default['private']['mail']['vmail']['home'] = '/home/vmail'
default['private']['mail']['vmail']['trash'] = '/home/vmail/.trash'
# end vmail

# postgres
default['private']['mail']['postgres']['version'] = '12'
default['private']['mail']['postgres']['port'] = 5432
# end postgres

# postfixadmin
default['private']['mail']['postfixadmin']['user'] = 'postfixadmin'
default['private']['mail']['postfixadmin']['group'] = 'postfixadmin'

default['private']['mail']['postfixadmin']['version'] = '3.2.3'
default['private']['mail']['postfixadmin']['url'] =
  'https://github.com/postfixadmin/postfixadmin/archive/postfixadmin-%{version}.tar.gz'
default['private']['mail']['postfixadmin']['checksum'] =
  'dae88f8166804997386bdf2454a62afc9bc768f0e4b53f46003d2766cebf31c0'

default['private']['mail']['postfixadmin']['database']['name'] = 'vmail'
default['private']['mail']['postfixadmin']['database']['locale'] = 'en_US.utf8'
default['private']['mail']['postfixadmin']['database']['user'] = 'postfixadmin'

default['private']['mail']['postfixadmin']['php_fpm_pool']['max_childen'] = 5
default['private']['mail']['postfixadmin']['php_fpm_pool']['start_servers'] = 2
default['private']['mail']['postfixadmin']['php_fpm_pool']['min_spare_servers'] = 1
default['private']['mail']['postfixadmin']['php_fpm_pool']['max_spare_servers'] = 3
default['private']['mail']['postfixadmin']['php_fpm_pool']['max_requests'] = 100
default['private']['mail']['postfixadmin']['php_fpm_pool']['memory_limit'] = '64M'
default['private']['mail']['postfixadmin']['php_fpm_pool']['listen'] =
  '/var/run/php-fpm-postfixadmin.sock'

default['private']['mail']['postfixadmin']['fqdn'] = nil
default['private']['mail']['postfixadmin']['default_server'] = true
default['private']['mail']['postfixadmin']['access_log_options'] = 'combined'
default['private']['mail']['postfixadmin']['error_log_options'] = 'error'
default['private']['mail']['postfixadmin']['hsts_max_age'] = 15_724_800
default['private']['mail']['postfixadmin']['oscp_stapling'] = true
default['private']['mail']['postfixadmin']['enable_setup_page'] = false
# end postfixadmin

# postfix
default['private']['mail']['postfix']['database']['user'] = 'postfix'
default['private']['mail']['postfix']['fqdn'] = nil

# end postfix

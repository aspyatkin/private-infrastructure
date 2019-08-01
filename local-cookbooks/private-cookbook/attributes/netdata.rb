default['private']['netdata']['git_repository'] = 'https://github.com/netdata/netdata.git'
default['private']['netdata']['git_revision'] = 'v1.15.0'

default['private']['netdata']['master']['listen']['host'] = '0.0.0.0'
default['private']['netdata']['master']['listen']['port'] = 19999
default['private']['netdata']['master']['stream'] = {}
default['private']['netdata']['master']['history'] = 3600

default['private']['netdata']['slave']['enabled'] = false
default['private']['netdata']['slave']['stream']['destination'] = nil
default['private']['netdata']['slave']['stream']['name'] = nil

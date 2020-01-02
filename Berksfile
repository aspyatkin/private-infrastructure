require './lib/helpers'
source 'https://api.berkshelf.com'

solver :gecode, :preferred

cookbook 'build-essential'
cookbook 'ntp'
cookbook 'git', '~> 9.0.0'
cookbook 'locale', '~> 2.0.1'
cookbook 'poise-python', '1.7.0'
cookbook 'sockd', '~> 0.1.0'

github_cookbook 'netdata', 'jmadureira/netdata-cookbook', branch: '7858ca3cedac092db212f7497891544c6f5fc200'
github_cookbook 'personal-website', 'aspyatkin/personal-website-cookbook', tag: 'v2.2.0'
github_cookbook 'ssmtp-lwrp', 'aspyatkin/ssmtp-lwrp-cookbook', tag: 'v0.1.0'

local_cookbook 'private', './local-cookbooks/private-cookbook'

# github_cookbook 'ctf-moscow-2019-101', 'VolgaCTF/ctf-moscow-2019-101-cookbook', tag: 'v1.0.0'
# github_cookbook 'volgactf-final', 'VolgaCTF/volgactf-final-cookbook', tag: 'v1.4.2'

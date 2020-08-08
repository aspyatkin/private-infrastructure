require './lib/helpers'
source 'https://api.berkshelf.com'

solver :gecode, :preferred

cookbook 'build-essential'
cookbook 'ntp'
cookbook 'git', '~> 9.0.0'
cookbook 'locale', '~> 2.0.1'
cookbook 'poise-python', '1.7.0'
cookbook 'sockd', '~> 0.1.0'

github_cookbook 'netdata', 'jmadureira/netdata-cookbook', branch: '336d91d15098d6240d2861fb992be5f52a318005'
github_cookbook 'cronic', 'aspyatkin/cronic-cookbook', tag: 'v2.0.1'
github_cookbook 'personal-website', 'aspyatkin/personal-website-cookbook', tag: 'v2.3.0'
github_cookbook 'ssmtp-lwrp', 'aspyatkin/ssmtp-lwrp-cookbook', tag: 'v0.2.0'

local_cookbook 'private', './local-cookbooks/private-cookbook'

# github_cookbook 'ctf-moscow-2019-101', 'VolgaCTF/ctf-moscow-2019-101-cookbook', tag: 'v1.0.0'
# github_cookbook 'volgactf-final', 'VolgaCTF/volgactf-final-cookbook', tag: 'v1.4.2'
github_cookbook 'volgactf-qualifier', 'VolgaCTF/volgactf-qualifier-cookbook', tag: 'v2.0.0'

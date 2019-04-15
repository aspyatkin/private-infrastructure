require './lib/helpers'
source 'https://api.berkshelf.com'

solver :gecode, :preferred

cookbook 'build-essential'
cookbook 'ntp'
cookbook 'git', '~> 9.0.0'
cookbook 'locale', '~> 2.0.1'
cookbook 'poise-python', '1.7.0'
cookbook 'sockd', '~> 0.1.0'

github_cookbook 'personal-website', 'aspyatkin/personal-website-cookbook', tag: 'v2.2.0'
github_cookbook 'latest-nodejs', 'aspyatkin/latest-nodejs-cookbook', tag: 'v2.0.0'

local_cookbook 'private', './local-cookbooks/private-cookbook'

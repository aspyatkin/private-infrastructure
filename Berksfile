require './lib/helpers'
source 'https://api.berkshelf.com'

solver :gecode, :preferred

cookbook 'build-essential'
cookbook 'ntp'
cookbook 'git', '~> 9.0.0'
cookbook 'locale', '~> 2.0.1'
cookbook 'poise-python', '1.7.0'
cookbook 'ufw', '~> 3.1.1'
cookbook 'dhparam', '~> 1.0.1'
cookbook 'nsd', '~> 0.3.0'
cookbook 'ngx', '~> 1.1.0'
cookbook 'redirect', '~> 1.4.1'
cookbook 'sockd', '~> 0.1.0'

github_cookbook 'dotfiles', 'aspyatkin/dotfiles-cookbook', tag: 'v1.4.0'
github_cookbook 'latest-git', 'aspyatkin/latest-git', tag: 'v1.5.0'
github_cookbook 'latest-nodejs', 'aspyatkin/latest-nodejs', tag: 'v1.6.0'
github_cookbook 'nginx-amplify', 'aspyatkin/nginx-amplify-cookbook', tag: 'v1.0.0'
github_cookbook 'personal-website', 'aspyatkin/personal-website-cookbook', tag: 'v1.15.0'

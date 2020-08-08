name 'private'
maintainer 'Alexander Pyatkin'
maintainer_email 'aspyatkin@gmail.com'
license 'MIT'
description 'Install and configure private infrastructure'
version '1.0.0'

depends 'ntp', '~> 3.6.2'
depends 'firewall', '~> 2.7.0'

depends 'instance', '~> 2.0.1'
depends 'secret', '~> 1.0.0'
depends 'cronic', '~> 2.0.1'
depends 'nodejs', '~> 6.0.0'
depends 'sockd', '~> 0.1.1'
depends 'personal-website', '~> 2.3.0'
depends 'ruby_rbenv', '>= 2.5.0'
depends 'ssh-private-keys', '~> 2.0.0'
depends 'nsd', '~> 0.4.1'
depends 'vpn', '~> 0.4.0'

depends 'ngx', '~> 2.2.0'
depends 'ngx-modules', '~> 1.3.0'
depends 'logrotate', '~> 2.2.0'
depends 'dhparam', '~> 2.0.0'
depends 'tls', '~> 3.2.0'
depends 'redirect', '~> 2.1.0'
depends 'ssmtp-lwrp', '~> 0.2.0'
depends 'netdata', '~> 0.4.1'
depends 'htpasswd', '~> 0.3.0'

depends 'postgresql', '~> 7.1.5'
depends 'php', '~> 7.0.0'
depends 'ark', '~> 4.0.0'

gem 'htauth'

# depends 'volgactf-final', '~> 1.4.2'
# depends 'ctf-moscow-2019-101'
depends 'volgactf-qualifier', '~> 2.0.0'

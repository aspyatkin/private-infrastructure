require 'digest/sha1'

module ChefCookbook
  module Private
    class PostfixadminHelper
      def initialize(node)
        @secret = ::ChefCookbook::Secret::Helper.new(node)
      end

      def setup_password
        salt = @secret.get('postfixadmin:setup_password:salt')
        password = @secret.get('postfixadmin:setup_password:password')
        "#{salt}:#{::Digest::SHA1.hexdigest("#{salt}:#{password}")}"
      end
    end
  end
end

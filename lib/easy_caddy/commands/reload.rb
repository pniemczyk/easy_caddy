# frozen_string_literal: true

require_relative '../caddy'
require_relative '../paths'

module EasyCaddy
  module Commands
    class Reload
      def call
        Caddy.validate!(Paths.caddyfile)
        Caddy.reload(Paths.caddyfile)
        puts '  Caddy reloaded.'
      end
    end
  end
end

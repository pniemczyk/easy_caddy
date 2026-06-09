# frozen_string_literal: true

require_relative 'register_helpers'

module EasyCaddy
  module Commands
    # Foreground command for Procfile.dev.
    # Registers the project Caddyfile on start, blocks until SIGTERM/SIGINT,
    # then unregisters and exits cleanly.
    class Run
      include RegisterHelpers

      def initialize(config_path:, site:)
        @config_path = config_path
        @site        = site
      end

      def call
        @registered_name = register(@config_path, @site)

        cleanup = proc do
          puts "\n  [ecaddy] Shutting down — removing #{@registered_name}..."
          unregister(@registered_name)
          exit 0
        end

        Signal.trap('TERM', &cleanup)
        Signal.trap('INT',  &cleanup)

        puts "  [ecaddy] Watching. Send SIGTERM or Ctrl-C to unregister."
        loop { sleep 5 }
      end
    end
  end
end

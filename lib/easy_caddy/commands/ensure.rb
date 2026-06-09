# frozen_string_literal: true

require_relative 'register_helpers'

module EasyCaddy
  module Commands
    # One-shot: copies the project Caddyfile into global sites/, reloads Caddy, then exits.
    # Site stays registered until `ecaddy down NAME` or `ecaddy remove NAME`.
    class Ensure
      include RegisterHelpers

      def initialize(config_path:, site:)
        @config_path = config_path
        @site        = site
      end

      def call
        register(@config_path, @site)
      end
    end
  end
end

# frozen_string_literal: true

require_relative '../paths'
require_relative '../registry'
require_relative '../caddy'

module EasyCaddy
  module Commands
    class Edit
      def initialize(name:)
        @name     = name.downcase
        @registry = Registry.load
      end

      def call
        site = @registry.find(@name)
        unless site
          warn "  Site '#{@name}' is not registered."
          exit 1
        end

        file = site.enabled ? Paths.site_file(@name) : Paths.disabled_file(@name)
        unless file.exist?
          warn "  Fragment file not found: #{file}"
          exit 1
        end

        editor = ENV.fetch('EDITOR', 'vi')
        system("#{editor} #{file}")
        Caddy.validate!(Paths.caddyfile)
        Caddy.reload(Paths.caddyfile) if site.enabled
        puts "  Saved and reloaded."
      end
    end
  end
end

# frozen_string_literal: true

require_relative '../paths'
require_relative '../registry'
require_relative '../caddy'
require_relative '../site'

module EasyCaddy
  module Commands
    class Up
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

        if site.enabled
          puts "  '#{@name}' is already up."
          return
        end

        disabled = Paths.disabled_file(@name)
        unless disabled.exist?
          warn "  Fragment not found in disabled/: #{disabled}"
          exit 1
        end

        disabled.rename(Paths.site_file(@name))
        @registry.update(Site.new(name: site.name, enabled: true, source_path: site.source_path))
        Caddy.validate!(Paths.caddyfile)
        Caddy.reload(Paths.caddyfile)
        puts "  '#{@name}' is up."
      end
    end
  end
end

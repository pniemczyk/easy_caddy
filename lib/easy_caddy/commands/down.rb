# frozen_string_literal: true

require_relative '../paths'
require_relative '../registry'
require_relative '../caddy'
require_relative '../site'

module EasyCaddy
  module Commands
    class Down
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

        if !site.enabled
          puts "  '#{@name}' is already down."
          return
        end

        active = Paths.site_file(@name)
        unless active.exist?
          warn "  Fragment not found in sites/: #{active}"
          exit 1
        end

        Paths.disabled_dir.mkpath
        active.rename(Paths.disabled_file(@name))
        @registry.update(Site.new(name: site.name, enabled: false, source_path: site.source_path))
        Caddy.reload(Paths.caddyfile)
        puts "  '#{@name}' is down. Run `ecaddy up #{@name}` to bring it back."
      end
    end
  end
end

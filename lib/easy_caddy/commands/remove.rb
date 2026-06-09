# frozen_string_literal: true

require_relative '../paths'
require_relative '../registry'
require_relative '../caddy'

module EasyCaddy
  module Commands
    class Remove
      def initialize(name:, force:, prompt:)
        @name     = name.downcase
        @force    = force
        @prompt   = prompt
        @registry = Registry.load
      end

      def call
        site = @registry.find(@name)
        unless site
          warn "  Site '#{@name}' is not registered."
          exit 1
        end

        unless @force
          unless @prompt.yes?("Remove #{@name} and delete its Caddy fragment?")
            puts '  Aborted.'
            return
          end
        end

        [Paths.site_file(@name), Paths.disabled_file(@name)].each do |f|
          f.delete if f.exist?
        end

        @registry.remove(@name)
        Caddy.reload(Paths.caddyfile)
        puts "  Removed '#{@name}'."
      end
    end
  end
end

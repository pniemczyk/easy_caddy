# frozen_string_literal: true

require 'English'
require_relative 'paths'

module EasyCaddy
  module Caddy
    BINARY = 'caddy'

    def self.installed?
      system('which caddy > /dev/null 2>&1')
    end

    def self.validate(caddyfile = Paths.caddyfile)
      system("#{BINARY} validate --config #{caddyfile} 2>&1")
    end

    def self.validate!(caddyfile = Paths.caddyfile)
      return unless caddyfile.exist?

      out = `#{BINARY} validate --config #{caddyfile} 2>&1`
      raise "Caddy config invalid:\n#{out}" unless $CHILD_STATUS.success?
    end

    def self.reload(caddyfile = Paths.caddyfile)
      unless caddyfile.exist?
        warn '  [ecaddy] Skipping reload — global Caddyfile not found. Run `ecaddy setup` first.'
        return
      end

      out = `#{BINARY} reload --config #{caddyfile} 2>&1`
      raise "Caddy reload failed:\n#{out}" unless $CHILD_STATUS.success?
    end

    def self.trust
      system("#{BINARY} trust")
    end

    def self.running?
      pid = brew_service_pid
      pid && pid > 0
    end

    def self.start_service
      system('brew services start caddy')
    end

    def self.restart_service
      system('brew services restart caddy')
    end

    def self.brew_service_pid
      output = `brew services list 2>/dev/null | grep '^caddy '`
      m = output.match(/(\d+)/)
      m&.captures&.first&.to_i
    end

    def self.process_pid
      out = `pgrep -f 'caddy run' 2>/dev/null`.strip
      return nil if out.empty?

      out.lines.first.to_i
    end

    def self.install_via_brew
      system('brew install caddy')
    end
  end
end

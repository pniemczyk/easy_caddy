# frozen_string_literal: true

require_relative '../registry'
require_relative '../caddy'
require_relative '../conflicts'
require_relative '../paths'

module EasyCaddy
  module Commands
    class Status
      def call
        running = Caddy.running?
        puts "  Caddy service: #{running ? 'running' : 'STOPPED'}"
        puts "  Config:        #{Paths.caddyfile}"
        puts

        registry = Registry.load
        sites    = registry.all

        if sites.empty?
          puts '  No sites registered.'
          return
        end

        dead_msgs = Conflicts.doctor(registry: registry)
          .select { |f| f.severity == 'INFO' }
          .map(&:message)

        sites.each do |s|
          site_dead = dead_msgs.any? { |m| m.start_with?(s.name) }
          label     = !s.enabled ? 'down' : (site_dead ? 'up (app not running)' : 'up')
          puts "  #{s.name.ljust(20)} #{label}"
          puts "    fragment: #{Paths.site_file(s.name)}" if s.enabled
          puts "    source:   #{s.source_path}" if s.source_path
        end
      end
    end
  end
end

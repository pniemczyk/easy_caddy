# frozen_string_literal: true

require_relative '../registry'
require_relative '../paths'
require_relative '../parser'

module EasyCaddy
  module Commands
    class List
      def initialize(format: 'table')
        @format   = format
        @registry = Registry.load
      end

      def call
        sites = @registry.all
        if sites.empty?
          puts '  No sites registered. Use `ecaddy run --config ./Caddyfile --site NAME` to add one.'
          return
        end

        if @format == 'json'
          require 'json'
          puts JSON.generate(sites.map { |s| row_data(s) })
          return
        end

        require 'tty-table'
        rows = sites.map { |s| row_data(s).values }

        table = TTY::Table.new(
          header: ['Name', 'Status', 'Domains', 'Ports', 'Source'],
          rows:   rows
        )
        puts table.render(:unicode, padding: [0, 1])
      end

      private

      def row_data(site)
        frag   = Paths.site_file(site.name)
        parsed = frag.exist? ? Parser.parse(frag.read) : nil
        {
          name:   site.name,
          status: site.enabled ? 'up' : 'down',
          domains: parsed&.domains&.join(', ') || '-',
          ports:   parsed&.ports&.join(', ') || '-',
          source:  site.source_path || '-'
        }
      end
    end
  end
end

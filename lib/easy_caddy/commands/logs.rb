# frozen_string_literal: true

require_relative '../registry'
require_relative '../paths'
require_relative '../parser'

module EasyCaddy
  module Commands
    # Tails Caddy access/error log files for a registered site.
    class Logs
      def initialize(site:, lines:, follow:)
        @site   = site
        @lines  = lines
        @follow = follow
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def call
        registry = Registry.load
        entry    = registry.find(@site)
        abort "  [ecaddy] No site '#{@site}' in registry. Run `ecaddy list` to see registered sites." unless entry

        fragment = resolve_fragment(entry)
        abort "  [ecaddy] Fragment not found for '#{@site}' in sites/ or disabled/." unless fragment

        paths = Parser.parse(File.read(fragment)).log_paths
        if paths.empty?
          puts "  [ecaddy] No 'output file' log directives found in #{fragment}."
          puts '           Add a log block to your Caddyfile, e.g.:'
          puts '             log { output file log/caddy.log }'
          return
        end

        paths.each do |p|
          next if File.exist?(p)

          puts "  [ecaddy] Note: #{p} not yet created (Caddy writes it on first request)."
        end

        existing = paths.select { |p| File.exist?(p) }
        if existing.empty?
          puts '  [ecaddy] No log files exist yet. Make a request to the site first.'
          return
        end

        tail_args = @follow ? ['-F'] : ['-n', @lines.to_s]
        exec('tail', *tail_args, *existing)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      private

      def resolve_fragment(entry)
        enabled  = Paths.site_file(entry.name)
        disabled = Paths.disabled_file(entry.name)
        return enabled  if enabled.exist?
        return disabled if disabled.exist?

        nil
      end
    end
  end
end

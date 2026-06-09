# frozen_string_literal: true

require_relative 'registry'
require_relative 'paths'
require_relative 'parser'

module EasyCaddy
  class Conflicts
    Finding = Data.define(:severity, :message, :hint)

    # Check a fragment file about to be written for domain/port collisions with existing enabled sites.
    # skip_name: the site being updated (exclude it from collision checks against itself).
    def self.check(name:, content:, registry:, skip_name: nil)
      new(name: name, content: content, registry: registry, skip_name: skip_name).check
    end

    def self.doctor(registry:)
      new(name: nil, content: nil, registry: registry, skip_name: nil).doctor
    end

    def initialize(name:, content:, registry:, skip_name:)
      @name      = name
      @content   = content
      @registry  = registry
      @skip_name = skip_name
    end

    def check
      return [] unless @content

      incoming = Parser.parse(@content)
      findings = []
      findings += domain_conflicts(incoming.domains)
      findings += port_conflicts(incoming.ports)
      findings
    end

    def doctor
      findings = []
      findings += cross_site_conflicts
      findings += dead_upstream_findings
      findings
    end

    private

    def domain_conflicts(incoming_domains)
      existing_domains = enabled_site_data
        .reject { |name, _| name == (@skip_name || @name) }
        .values.flat_map { |d| d[:domains] }

      (incoming_domains & existing_domains).map do |d|
        owner = enabled_site_data.find { |_, data| data[:domains].include?(d) }&.first
        Finding.new(
          severity: 'BLOCK',
          message:  "Domain #{d} is already registered by '#{owner}'.",
          hint:     "Run `ecaddy list` to see which project owns this domain."
        )
      end
    end

    def port_conflicts(incoming_ports)
      findings = []
      existing_ports = enabled_site_data
        .reject { |name, _| name == (@skip_name || @name) }
        .transform_values { |d| d[:ports] }

      incoming_ports.each do |port|
        existing_ports.each do |owner, ports|
          next unless ports.include?(port)

          findings << Finding.new(
            severity: 'BLOCK',
            message:  "Port #{port} is already used by '#{owner}'.",
            hint:     "Choose a different port or run `ecaddy list` to see all ports in use."
          )
        end
      end
      findings
    end

    def cross_site_conflicts
      findings = []
      seen_ports   = {}
      seen_domains = {}

      enabled_site_data.each do |name, data|
        data[:ports].each do |p|
          if seen_ports[p]
            findings << Finding.new(
              severity: 'BLOCK',
              message:  "Port #{p} is shared by '#{seen_ports[p]}' and '#{name}'.",
              hint:     "Edit the conflicting Caddyfile and run `ecaddy run` again."
            )
          else
            seen_ports[p] = name
          end
        end

        data[:domains].each do |d|
          if seen_domains[d]
            findings << Finding.new(
              severity: 'BLOCK',
              message:  "Domain #{d} is shared by '#{seen_domains[d]}' and '#{name}'.",
              hint:     "Edit the conflicting Caddyfile and run `ecaddy run` again."
            )
          else
            seen_domains[d] = name
          end
        end
      end
      findings
    end

    def dead_upstream_findings
      @registry.all.flat_map do |site|
        fragment = Paths.site_file(site.name)
        next [] unless fragment.exist?

        parsed = Parser.parse(fragment.read)
        parsed.ports.filter_map do |port|
          next if tcp_open?(port)

          Finding.new(
            severity: 'INFO',
            message:  "#{site.name}: upstream localhost:#{port} is not listening.",
            hint:     "Start your app on port #{port}."
          )
        end
      end
    end

    # Parse all enabled fragment files once, memoised.
    def enabled_site_data
      @enabled_site_data ||= @registry.all.each_with_object({}) do |site, h|
        frag = Paths.site_file(site.name)
        next unless frag.exist?

        parsed = Parser.parse(frag.read)
        h[site.name] = { domains: parsed.domains, ports: parsed.ports }
      end
    end

    def tcp_open?(port)
      require 'socket'
      TCPSocket.new('localhost', port).close
      true
    rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT
      false
    end
  end
end

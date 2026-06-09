# frozen_string_literal: true

module EasyCaddy
  # Minimal Caddyfile parser — extracts site blocks, domains, and reverse_proxy ports.
  # Not a full grammar; covers the patterns ecaddy generates.
  class Parser
    ParsedConfig = Data.define(:domains, :ports, :log_paths)

    def self.parse(content)
      new(content).parse
    end

    def initialize(content)
      @content = content
    end

    def parse
      domains   = []
      ports     = []
      log_paths = []

      @content.scan(/^([\w.*-]+\.localhost)\s*\{/) { domains << Regexp.last_match(1) }
      @content.scan(/reverse_proxy\s+localhost:(\d+)/) { ports << Regexp.last_match(1).to_i }
      @content.scan(/\boutput\s+file\s+(\S+)/) { log_paths << Regexp.last_match(1) }

      ParsedConfig.new(domains: domains.uniq, ports: ports.uniq, log_paths: log_paths.uniq)
    end

    # Derive a project name from the first non-vite domain.
    # "fishme.localhost" → "fishme", "vite.fishme.localhost" is skipped.
    def self.infer_name(content)
      domains = parse(content).domains
      primary = domains.reject { |d| d.start_with?('vite.') }.first
      return unless primary

      primary.sub(/\.localhost$/, '')
    end
  end
end

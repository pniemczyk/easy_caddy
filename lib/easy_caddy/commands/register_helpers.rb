# frozen_string_literal: true

require 'fileutils'
require 'socket'
require 'openssl'
require_relative '../error'
require_relative '../paths'
require_relative '../registry'
require_relative '../conflicts'
require_relative '../caddy'
require_relative '../site'
require_relative '../parser'

module EasyCaddy
  module Commands
    # rubocop:disable Metrics/ModuleLength
    module RegisterHelpers
      private

      # Copies config_path into ~/.config/caddy/sites/<name>.caddy and reloads.
      # Returns the site name on success.
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
      def register(config_path, name)
        raise Error, 'Pass --site NAME to identify this project.' unless name

        config_path = File.expand_path(config_path)
        raise Error, "Config not found: #{config_path}" unless File.exist?(config_path)

        content  = File.read(config_path)
        registry = Registry.load
        existing = registry.find(name)

        findings = Conflicts.check(name: name, content: content, registry: registry,
                                   skip_name: existing&.name)
        blocks = findings.select { |f| f.severity == 'BLOCK' }
        unless blocks.empty?
          blocks.each { |f| warn "  BLOCK: #{f.message}\n         Hint: #{f.hint}" }
          raise Error, 'Aborting due to conflict.'
        end

        Paths.sites_dir.mkpath
        rewritten = ensure_log_mode(absolutize_log_paths(content, File.dirname(config_path)))
        Paths.site_file(name).write(rewritten)

        ensure_log_dirs(rewritten)

        site = Site.new(name: name, enabled: true, source_path: config_path)
        existing ? registry.update(site) : registry.add(site)

        Caddy.validate!(Paths.caddyfile)
        Caddy.reload(Paths.caddyfile)

        puts "  [ecaddy] #{name} registered (#{config_path})"
        probe_tls(Parser.parse(rewritten).domains)
        name
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength

      # Rewrite `output file <relative>` log paths to absolute paths so Caddy can
      # write logs regardless of its working directory when running as a service.
      def absolutize_log_paths(content, base_dir)
        content.gsub(/(\boutput\s+file\s+)(\S+)/) do
          prefix = Regexp.last_match(1)
          path   = Regexp.last_match(2)
          absolute = File.expand_path(path, base_dir)
          "#{prefix}#{absolute}"
        end
      end

      # Guarantee every `output file` log directive sets a group-writable mode, so a
      # root-run Caddy's logs (and rolled files) stay openable by the staff-group user that
      # runs `caddy validate`/`reload`. Leaves an explicit `mode` untouched.
      def ensure_log_mode(content)
        content.gsub(/(\boutput\s+file\s+\S+)(\s*\{[^}]*\})?/m) do
          directive = Regexp.last_match(1)
          block     = Regexp.last_match(2)
          next "#{directive} {\n    mode #{Caddy::LOG_FILE_MODE}\n  }" if block.nil?
          next "#{directive}#{block}" if block.match?(/\bmode\b/)

          "#{directive}#{block.sub('{', "{\n    mode #{Caddy::LOG_FILE_MODE}")}"
        end
      end

      def ensure_log_dirs(content)
        Parser.parse(content).log_paths.each do |path|
          ensure_log_writable(path)
        end
      end

      # Make sure each log path exists and is writable by the current user.
      # Caddy validates configs by *opening* every log file, so a stray
      # root-owned file (left over from an earlier `sudo` run) makes
      # validation fail with a confusing "permission denied".
      def ensure_log_writable(path)
        dir = File.dirname(path)
        FileUtils.mkdir_p(dir)
        FileUtils.touch(path) unless File.exist?(path)
        return if File.writable?(path) && File.writable?(dir)

        raise Error, build_log_permission_error(path)
      rescue Errno::EACCES, Errno::EPERM
        raise Error, build_log_permission_error(path)
      end

      # rubocop:disable Metrics/MethodLength
      def build_log_permission_error(path)
        owner =
          begin
            require 'etc'
            Etc.getpwuid(File.stat(path).uid).name if File.exist?(path)
          rescue StandardError
            nil
          end
        user = ENV['USER'] || Etc.getlogin

        owner_line = owner ? "  Current owner: #{owner}\n" : ''
        <<~MSG.strip
          Cannot write to Caddy log file: #{path}
          #{owner_line}  Caddy runs as root and created this log 0600; `caddy validate` runs as you
          (#{user}) and can't open it. Make it group-writable once:

            sudo chmod #{Caddy::LOG_FILE_MODE} #{path}

          or run `ecaddy audit --fix` to do it interactively. Re-registering keeps the mode,
          so it won't recur after log rolls. Then re-run the same `ecaddy` command.
        MSG
      end
      # rubocop:enable Metrics/MethodLength

      def probe_tls(domains)
        domains.each do |domain|
          ok = tls_handshake_ok?(domain)
          next if ok

          warn "  [ecaddy] WARN  #{domain}: TLS handshake failed (Caddy may not be serving :443 yet)."
          warn '                 Run `ecaddy audit` to diagnose.'
        end
      end

      # rubocop:disable Metrics/MethodLength
      def tls_handshake_ok?(domain)
        require 'timeout'
        Timeout.timeout(1) do
          tcp = TCPSocket.new('localhost', 443)
          ssl = OpenSSL::SSL::SSLSocket.new(tcp)
          ssl.hostname   = domain
          ssl.sync_close = true
          ssl.connect
          ssl.close
        end
        true
      rescue StandardError
        false
      end
      # rubocop:enable Metrics/MethodLength

      def unregister(name)
        Paths.site_file(name).delete if Paths.site_file(name).exist?

        registry = Registry.load
        registry.remove(name)

        begin
          Caddy.reload(Paths.caddyfile)
        rescue StandardError
          nil
        end
        puts "  [ecaddy] #{name} unregistered."
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end

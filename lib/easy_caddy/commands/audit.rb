# frozen_string_literal: true

require 'English'
require 'socket'
require 'openssl'
require 'timeout'
require 'tty-prompt'
require_relative '../registry'
require_relative '../paths'
require_relative '../caddy'
require_relative '../parser'
require_relative '../conflicts'

module EasyCaddy
  module Commands
    # Prints a full system + TLS + site snapshot with per-domain TLS handshake probes.
    # With fix: true, prompts to apply a remedy for each actionable finding, with
    # automatic escalation to a chained next_fix when the primary fix doesn't resolve it.
    # rubocop:disable Metrics/ClassLength
    class Audit
      # ANSI colours — fall back gracefully if $stdout is not a TTY.
      RED   = "\e[31m"
      GREEN = "\e[32m"
      YELLW = "\e[33m"
      RESET = "\e[0m"

      Fix = Data.define(:label, :description, :command, :verify, :escalation, :next_fix)

      def initialize(site: nil, fix: false)
        @site_filter = site
        @fix_mode    = fix
        @fixes       = []
      end

      def call
        section('SYSTEM')
        print_system

        section('TLS READINESS')
        print_tls_readiness

        section('SITES')
        print_sites

        section('CONFLICTS')
        print_conflicts

        run_fixes if @fix_mode
      end

      private

      # ── formatting helpers ──────────────────────────────────────────────

      def section(title)
        puts
        puts "── #{title} #{'─' * [0, 60 - title.length].max}"
      end

      def ok(msg) = puts("  #{GREEN}✓#{RESET}  #{msg}")
      def info(msg) = puts("     #{msg}")

      # rubocop:disable Metrics/MethodLength
      def fail(msg, hint: nil, fix: nil)
        puts "  #{RED}✗#{RESET}  #{msg}"
        puts "       hint: #{hint}" if hint
        return unless fix

        @fixes << Fix.new(
          label: msg,
          description: fix[:description],
          command: fix[:command],
          verify: fix[:verify],
          escalation: fix[:escalation],
          next_fix: fix[:next_fix]
        )
      end
      # rubocop:enable Metrics/MethodLength

      # rubocop:disable Metrics/MethodLength
      def warn(msg, hint: nil, fix: nil)
        puts "  #{YELLW}!#{RESET}  #{msg}"
        puts "       hint: #{hint}" if hint
        return unless fix

        @fixes << Fix.new(
          label: msg,
          description: fix[:description],
          command: fix[:command],
          verify: fix[:verify],
          escalation: fix[:escalation],
          next_fix: fix[:next_fix]
        )
      end
      # rubocop:enable Metrics/MethodLength

      # ── system section ──────────────────────────────────────────────────

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def print_system
        if Caddy.installed?
          version = `caddy version 2>/dev/null`.strip
          ok("Caddy installed: #{version}")
        else
          fail('Caddy not installed',
               hint: 'Install via Homebrew.',
               fix: {
                 description: 'Install Caddy',
                 command: 'brew install caddy',
                 verify: -> { Caddy.installed? },
                 escalation: 'Install still failed. Check `brew doctor`, or install manually from caddyserver.com.',
                 next_fix: nil
               })
        end

        print_service_status

        caddyfile = Paths.caddyfile
        if caddyfile.exist?
          ok("Global Caddyfile: #{caddyfile}")
        else
          fail("Global Caddyfile missing: #{caddyfile}",
               hint: 'Run `ecaddy setup` to scaffold the global config.',
               fix: {
                 description: 'Scaffold global config',
                 command: 'ecaddy setup',
                 verify: -> { Paths.caddyfile.exist? },
                 escalation: 'Setup didn\'t write the Caddyfile. Re-run `ecaddy setup` and watch for errors.',
                 next_fix: nil
               })
        end
        brew_link = Paths.brew_caddyfile
        if brew_link.symlink? && brew_link.readlink == caddyfile
          ok("Brew symlink: #{brew_link} → #{caddyfile}")
        elsif brew_link.exist?
          warn("Brew symlink #{brew_link} points elsewhere",
               hint: 'Run `ecaddy setup` to fix the symlink.',
               fix: {
                 description: 'Fix brew symlink',
                 command: 'ecaddy setup',
                 verify: -> { Paths.brew_caddyfile.symlink? && Paths.brew_caddyfile.readlink == Paths.caddyfile },
                 escalation: 'Symlink still wrong. Remove it manually ' \
                              '(`rm /opt/homebrew/etc/Caddyfile`) and re-run `ecaddy setup`.',
                 next_fix: nil
               })
        else
          fail("Brew symlink missing: #{brew_link}",
               hint: 'Run `ecaddy setup` to create the symlink.',
               fix: {
                 description: 'Create brew symlink',
                 command: 'ecaddy setup',
                 verify: -> { Paths.brew_caddyfile.symlink? && Paths.brew_caddyfile.readlink == Paths.caddyfile },
                 escalation: 'Symlink still missing after setup. Re-run `ecaddy setup` and watch for errors.',
                 next_fix: nil
               })
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def print_service_status
        brew_pid = Caddy.brew_service_pid
        proc_pid = Caddy.process_pid

        if brew_pid
          ok("brew service running (PID #{brew_pid})")
        elsif proc_pid
          warn("brew service not started, but Caddy process #{proc_pid} is running",
               hint: 'Caddy was started outside brew (e.g. `caddy run` or sudo). ' \
                     'Ports :443/:80 will work, but it won\'t restart automatically. ' \
                     'To switch to the brew-managed service: stop it and run `brew services start caddy`.',
               fix: {
                 description: 'Stop external Caddy + start brew service',
                 command: "pkill -f 'caddy run'; brew services start caddy",
                 verify: -> { Caddy.brew_service_pid },
                 escalation: 'Brew service still not running — external Caddy may have ignored SIGTERM.',
                 next_fix: Fix.new(
                   label: 'External Caddy did not stop',
                   description: 'Force-kill external Caddy and restart via sudo',
                   command: "sudo pkill -9 -f 'caddy run'; sudo brew services restart caddy",
                   verify: -> { port_open?(443) || Caddy.brew_service_pid },
                   escalation: 'Still not running. Check `brew services info caddy`.',
                   next_fix: nil
                 )
               })
        else
          fail('Caddy is not running',
               hint: 'Start the brew service: `brew services start caddy`.',
               fix: {
                 description: 'Start Caddy via brew',
                 command: 'brew services start caddy',
                 verify: -> { Caddy.brew_service_pid },
                 escalation: 'Service still not up — brew user-mode may lack permission to bind low ports.',
                 next_fix: Fix.new(
                   label: 'Caddy still not running — trying with elevated privileges',
                   description: 'Start Caddy via sudo (creates a root LaunchDaemon, binds low ports)',
                   command: 'brew services stop caddy; sudo brew services start caddy',
                   verify: -> { port_open?(443) || Caddy.brew_service_pid },
                   escalation: 'Still not running. Check `brew services info caddy`.',
                   next_fix: nil
                 )
               })
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      # ── TLS readiness section ───────────────────────────────────────────

      # rubocop:disable Metrics/MethodLength
      def print_tls_readiness
        if caddy_ca_trusted?
          ok('Caddy Local Authority found in system keychain')
        else
          fail('Caddy Local Authority not found in keychain',
               hint: 'Run `caddy trust` to install the local root CA. ' \
                     'Without it, browsers show ERR_SSL_PROTOCOL_ERROR or NET::ERR_CERT_AUTHORITY_INVALID.',
               fix: {
                 description: 'Trust Caddy local CA',
                 command: 'caddy trust',
                 verify: -> { caddy_ca_trusted? },
                 escalation: 'CA not installed — installation into System keychain requires admin.',
                 next_fix: Fix.new(
                   label: 'Caddy CA still not trusted — trying with sudo',
                   description: 'Install CA into System keychain via sudo',
                   command: 'sudo caddy trust',
                   verify: -> { caddy_ca_trusted? },
                   escalation: 'CA still not in keychain. Check Keychain Access for \'Caddy Local Authority\'.',
                   next_fix: nil
                 )
               })
        end

        check_port(443, 'HTTPS (:443)')
        check_port(80,  'HTTP  (:80)')
      end
      # rubocop:enable Metrics/MethodLength

      def caddy_ca_trusted?
        # `find-certificate -p` dumps PEM; `verify-cert -p ssl` checks trust settings —
        # unlike bare `find-certificate` which only checks for presence.
        system(
          'security find-certificate -c "Caddy Local Authority" -p ' \
          '/Library/Keychains/System.keychain 2>/dev/null | ' \
          'security verify-cert -c /dev/stdin -p ssl > /dev/null 2>&1'
        )
      end

      def browser_trusts?(domain)
        # curl on macOS uses Secure Transport (same trust store as Chrome/Safari).
        # --resolve avoids DNS edge cases with .localhost
        system(
          "curl --silent --show-error --max-time 2 --resolve #{domain}:443:127.0.0.1 " \
          "-o /dev/null https://#{domain}/ 2>/dev/null"
        )
      end

      def port_open?(port)
        Timeout.timeout(0.5) { TCPSocket.new('127.0.0.1', port).close }
        true
      rescue StandardError
        false
      end

      # rubocop:disable Metrics/MethodLength
      def check_port(port, label)
        if port_open?(port)
          ok("#{label} is bound")
        else
          fail("#{label} is NOT bound",
               hint: 'Caddy may need `sudo` to bind low ports, or is not running.',
               fix: {
                 description: "Restart Caddy (to bind #{label})",
                 command: 'brew services restart caddy',
                 verify: -> { port_open?(port) },
                 escalation: "Port :#{port} still not bound — brew user-mode cannot bind ports below 1024.",
                 next_fix: Fix.new(
                   label: "#{label} still not bound — needs elevated privileges",
                   description: 'Stop user-mode Caddy and start as root (binds low ports). ' \
                                'Prompts for admin password.',
                   command: 'brew services stop caddy; sudo brew services restart caddy',
                   verify: -> { port_open?(port) },
                   escalation: "Still not bound. Another process may own :#{port} — " \
                                "check `sudo lsof -nP -i :#{port}`.",
                   next_fix: nil
                 )
               })
        end
      end
      # rubocop:enable Metrics/MethodLength

      # ── sites section ───────────────────────────────────────────────────

      def print_sites
        registry = Registry.load
        sites    = registry.all
        sites    = sites.select { |s| s.name == @site_filter } if @site_filter

        if sites.empty?
          info(@site_filter ? "No site '#{@site_filter}' in registry." : 'No sites registered.')
          return
        end

        sites.each { |s| print_site(s) }
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def print_site(site)
        puts
        puts "  Site: #{site.name}  [#{site.enabled ? 'enabled' : 'disabled'}]"
        info "source:   #{site.source_path || '(none)'}"

        fragment = site.enabled ? Paths.site_file(site.name) : Paths.disabled_file(site.name)
        unless fragment.exist?
          re_register_cmd = site.source_path ? "ecaddy ensure -c #{site.source_path} -s #{site.name}" : nil
          fail("fragment missing: #{fragment}",
               hint: 'Fragment file was deleted. Re-register from source.',
               fix: if re_register_cmd
                      {
                        description: 'Re-register from source',
                        command: re_register_cmd,
                        verify: -> { fragment.exist? },
                        escalation: 'Re-register didn\'t write the fragment. ' \
                                     'Check the source path exists and is readable.',
                        next_fix: nil
                      }
                    end)
          return
        end

        info "fragment: #{fragment}"
        parsed = Parser.parse(File.read(fragment))

        print_domains(parsed.domains)
        print_upstreams(parsed.ports)
        print_log_files(parsed.log_paths)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      # rubocop:disable Metrics/MethodLength
      def print_domains(domains)
        if domains.empty?
          warn 'No .localhost domains found in fragment'
          return
        end

        domains.each do |domain|
          handshake_ok, detail = tls_probe(domain)
          unless handshake_ok
            hint, fix = tls_hint_and_fix(detail, domain)
            fail("#{domain}  — TLS ✗  #{detail}", hint: hint, fix: fix)
            next
          end

          if browser_trusts?(domain)
            ok("#{domain}  — TLS ✓  browser-trusted ✓  #{detail}")
          else
            fail("#{domain}  — TLS ✓  browser-trust ✗  (Chrome will show ERR_CERT_AUTHORITY_INVALID)",
                 hint: 'Caddy CA is not installed into the System keychain with SSL trust. ' \
                       'Run `sudo caddy trust`.',
                 fix: browser_trust_fix(domain))
          end
        end
      end

      def browser_trust_fix(domain)
        {
          description: 'Install Caddy CA into System keychain',
          command: 'caddy trust',
          verify: -> { browser_trusts?(domain) },
          escalation: 'CA still not browser-trusted — System-keychain install requires admin.',
          next_fix: Fix.new(
            label: "#{domain} browser-trust still failing — needs sudo",
            description: 'Install CA into System keychain via sudo (browsers will honor it)',
            command: 'sudo caddy trust',
            verify: -> { browser_trusts?(domain) },
            escalation: 'Still not trusted. Open Keychain Access → System → search "Caddy Local Authority" → ' \
                        'set Trust → "When using this certificate: Always Trust".',
            next_fix: nil
          )
        }
      end

      def print_upstreams(ports)
        if ports.empty?
          info 'No reverse_proxy upstreams found'
        else
          ports.each do |port|
            if tcp_open?(port)
              ok("upstream localhost:#{port}  — listening")
            else
              warn("upstream localhost:#{port}  — NOT listening",
                   hint: "Start your app on port #{port}.")
            end
          end
        end
      end

      def print_log_files(log_paths)
        if log_paths.empty?
          info 'No log files configured (add a log { output file … } block)'
        else
          log_paths.each do |path|
            if File.exist?(path)
              ok("log #{path}  (#{humanize_bytes(File.size(path))})")
            else
              warn("log #{path}  — not yet created")
            end
          end
        end
      end
      # rubocop:enable Metrics/MethodLength

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def tls_hint_and_fix(detail, domain = nil)
        case detail
        when /connection refused/
          hint = 'Caddy is not listening on :443. Start the service.'
          fix  = {
            description: 'Start Caddy',
            command: 'brew services start caddy',
            verify: -> { port_open?(443) },
            escalation: 'Caddy still not on :443 — see the port-binding hint above.',
            next_fix: nil
          }
        when /internal error|alert 80/
          hint = 'Caddy aborted the TLS handshake — usually stale on-demand issuance state. ' \
                 'Try a reload; if that fails, restart Caddy.'
          fix  = {
            description: 'Reload Caddy config',
            command: "caddy reload --config #{Paths.brew_caddyfile}",
            verify: domain ? -> { tls_probe(domain).first } : nil,
            escalation: 'Reload didn\'t clear it. Try `brew services restart caddy`. ' \
                         'If still failing, the on-demand cert store may be corrupt — ' \
                         'see `~/Library/Application Support/Caddy/pki/`.',
            next_fix: nil
          }
        when /unknown ca|certificate|authority/i
          hint = "Caddy's local CA is not trusted by this machine."
          fix  = {
            description: 'Trust Caddy local CA',
            command: 'caddy trust',
            verify: domain ? -> { browser_trusts?(domain) } : -> { caddy_ca_trusted? },
            escalation: 'CA not installed — installation into System keychain requires admin.',
            next_fix: Fix.new(
              label: 'Caddy CA still not trusted — trying with sudo',
              description: 'Install CA into System keychain via sudo',
              command: 'sudo caddy trust',
              verify: domain ? -> { browser_trusts?(domain) } : -> { caddy_ca_trusted? },
              escalation: 'CA still not in keychain. Check Keychain Access for \'Caddy Local Authority\'.',
              next_fix: nil
            )
          }
        else
          hint = nil
          fix  = nil
        end
        [hint, fix]
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength
      def tls_probe(domain)
        Timeout.timeout(1) do
          tcp = TCPSocket.new('localhost', 443)
          ctx = OpenSSL::SSL::SSLContext.new
          ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
          ssl = OpenSSL::SSL::SSLSocket.new(tcp, ctx)
          ssl.hostname   = domain
          ssl.sync_close = true
          ssl.connect
          cn = ssl.peer_cert&.subject&.to_a&.find { |name, _| name == 'CN' }&.at(1) || '?'
          ssl.close
          [true, "cert CN=#{cn}"]
        end
      rescue Errno::ECONNREFUSED
        [false, 'connection refused on :443 (Caddy not running or not bound)']
      rescue StandardError => e
        [false, e.message.split("\n").first]
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength

      def tcp_open?(port)
        TCPSocket.new('localhost', port).close
        true
      rescue StandardError
        false
      end

      def humanize_bytes(bytes)
        return "#{bytes} B"                       if bytes < 1024
        return "#{(bytes / 1024.0).round(1)} KB"  if bytes < 1_048_576

        "#{(bytes / 1_048_576.0).round(1)} MB"
      end

      # ── conflicts section ───────────────────────────────────────────────

      # rubocop:disable Metrics/MethodLength
      def print_conflicts
        registry = Registry.load
        findings = Conflicts.doctor(registry: registry)

        if findings.empty?
          ok('No conflicts or dead upstreams detected')
          return
        end

        findings.each do |f|
          case f.severity
          when 'BLOCK' then fail("#{f.message}  Hint: #{f.hint}")
          when 'WARN'  then warn("#{f.message}  Hint: #{f.hint}")
          else              info("#{f.message}  Hint: #{f.hint}")
          end
        end
      end
      # rubocop:enable Metrics/MethodLength

      # ── fix loop ────────────────────────────────────────────────────────

      def run_fixes
        return if @fixes.empty?

        prompt            = TTY::Prompt.new
        @applied_commands = []

        section("FIXES (#{@fixes.length})")
        @fixes.each { |fix| run_fix(fix, prompt) }
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def run_fix(fix, prompt)
        if fix.verify&.call
          puts
          puts "  #{GREEN}✓#{RESET}  #{fix.label} — already resolved"
          return
        end

        puts
        puts "  Issue:   #{fix.label}"
        puts "  Fix:     #{fix.description}"
        puts "  Command: #{fix.command}"
        return unless prompt.yes?('  Apply?')

        if @applied_commands.include?(fix.command)
          puts "  #{YELLW}!#{RESET} already ran this command in this session — re-checking..."
        else
          ran = system(fix.command)
          unless ran
            puts "  #{RED}✗#{RESET} command failed to run"
            puts "       next: #{fix.escalation}" if fix.escalation
            run_fix(fix.next_fix, prompt) if fix.next_fix
            return
          end

          @applied_commands << fix.command
        end

        if fix.verify.nil?
          puts "  #{GREEN}✓#{RESET} applied"
          return
        end

        sleep 0.5
        if fix.verify.call
          puts "  #{GREEN}✓#{RESET} applied and verified"
        else
          puts "  #{YELLW}!#{RESET} applied, but the issue is still present"
          puts "       next: #{fix.escalation}" if fix.escalation
          run_fix(fix.next_fix, prompt) if fix.next_fix
        end
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    end
    # rubocop:enable Metrics/ClassLength
  end
end

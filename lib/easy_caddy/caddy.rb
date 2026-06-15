# frozen_string_literal: true

require 'English'
require 'net/http'
require 'uri'
require_relative 'error'
require_relative 'paths'

module EasyCaddy
  module Caddy
    BINARY = 'caddy'

    # Group-writable mode for Caddy log files. A root-run Caddy (needed to bind :443/:80)
    # creates logs the unprivileged user can't open during `caddy validate`/`reload`;
    # 0660 + macOS staff-group inheritance keeps them openable. See the log-permission fix.
    LOG_FILE_MODE = '0660'

    def self.installed?
      system('which caddy > /dev/null 2>&1')
    end

    def self.validate(caddyfile = Paths.caddyfile)
      system("#{BINARY} validate --config #{caddyfile} 2>&1")
    end

    def self.validate!(caddyfile = Paths.caddyfile)
      return unless caddyfile.exist?

      out = `#{BINARY} validate --config #{caddyfile} 2>&1`
      return if $CHILD_STATUS.success?

      raise Error, translate_validate_error(out)
    end

    # Caddy validate emits a wall of JSON log lines on stderr. Pull out the
    # actual error and, for common cases (log file permission), turn it into
    # an actionable message.
    # rubocop:disable Metrics/MethodLength
    def self.translate_validate_error(output)
      error_line = output.lines.find { |l| l.start_with?('Error:') }&.strip

      if error_line && error_line.match?(/setting up custom log.*permission denied/i)
        path = error_line[%r{open\s+(/\S+):\s*permission denied}, 1]
        hint =
          if path
            "Caddy runs as root and created this log 0600; validation runs as you and can't " \
            "open it.\nFix it once with:  sudo chmod #{LOG_FILE_MODE} #{path}\n" \
            'or run `ecaddy audit --fix` to do it interactively.'
          else
            'Check ownership of the log file referenced above, or run `ecaddy audit --fix`.'
          end
        return "Caddy config invalid — log file not writable:\n  #{error_line}\n\n#{hint}"
      end

      "Caddy config invalid:\n#{error_line || output}"
    end
    # rubocop:enable Metrics/MethodLength

    def self.reload(caddyfile = Paths.caddyfile)
      unless caddyfile.exist?
        warn '  [ecaddy] Skipping reload — global Caddyfile not found. Run `ecaddy setup` first.'
        return
      end

      out = `#{BINARY} reload --config #{caddyfile} 2>&1`
      raise Error, "Caddy reload failed:\n#{out}" unless $CHILD_STATUS.success?
    end

    def self.trust
      system("#{BINARY} trust")
    end

    # Runs `caddy trust` and captures stdout+stderr so callers can inspect failures.
    #
    # @return [Array(String, Boolean)] combined output and whether the command succeeded
    def self.trust_with_output
      out = `#{BINARY} trust 2>&1`
      [out, $CHILD_STATUS.success?]
    end

    def self.untrust
      system("#{BINARY} untrust")
    end

    # @return [Array(String, Boolean)] combined output and whether the command succeeded
    def self.untrust_with_output
      out = `#{BINARY} untrust 2>&1`
      [out, $CHILD_STATUS.success?]
    end

    ADMIN_ENDPOINT = 'http://localhost:2019/pki/ca/local'

    # Polls Caddy's admin API until it responds or the timeout elapses.
    #
    # @param timeout [Numeric] seconds to wait before giving up
    # @return [Boolean] true if the admin endpoint responded
    def self.wait_for_admin_endpoint(timeout: 5)
      deadline = Time.now + timeout
      until Time.now > deadline
        return true if admin_endpoint_reachable?

        sleep 0.25
      end
      false
    end

    def self.admin_endpoint_reachable?
      uri = URI(ADMIN_ENDPOINT)
      Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 1) do |http|
        http.get(uri.request_uri).is_a?(Net::HTTPSuccess)
      end
    rescue StandardError
      false
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

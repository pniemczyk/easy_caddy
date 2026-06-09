# frozen_string_literal: true

require_relative '../paths'
require_relative '../caddy'

module EasyCaddy
  module Commands
    class Setup
      GLOBAL_CADDYFILE_CONTENT = <<~CADDY
        {
          admin localhost:2019
        }

        import sites/*.caddy
      CADDY

      def initialize(prompt:)
        @prompt = prompt
      end

      def call
        step('Checking Caddy binary') { ensure_caddy_installed }
        step('Scaffolding config directories') { scaffold_dirs }
        step('Writing global Caddyfile') { write_caddyfile }
        step('Symlinking for brew services') { symlink_brew }
        step('Trusting local CA') { trust_ca }
        step('Starting caddy service') { start_service }
        print_success
      end

      private

      def step(label)
        print "  #{label}... "
        yield
        puts 'done'
      rescue StandardError => e
        puts "FAILED\n    #{e.message}"
        raise
      end

      def ensure_caddy_installed
        return if Caddy.installed?

        unless @prompt.yes?('caddy is not installed. Install via Homebrew now?')
          raise 'caddy is required. Install it with: brew install caddy'
        end

        Caddy.install_via_brew
        raise 'caddy installation failed' unless Caddy.installed?
      end

      def scaffold_dirs
        [Paths.root, Paths.sites_dir, Paths.disabled_dir].each(&:mkpath)
      end

      def write_caddyfile
        return if Paths.caddyfile.exist?

        Paths.caddyfile.write(GLOBAL_CADDYFILE_CONTENT)
      end

      def symlink_brew
        target  = Paths.caddyfile
        symlink = Paths.brew_caddyfile
        return if symlink.symlink? && symlink.readlink == target

        if symlink.exist? && !symlink.symlink?
          bak = "#{symlink}.bak.#{Time.now.strftime('%Y%m%d%H%M%S')}"
          symlink.rename(bak)
          puts "\n    Backed up existing #{symlink} → #{bak}"
        end

        symlink.parent.mkpath
        symlink.make_symlink(target)
      end

      def trust_ca
        puts "\n    Running `caddy trust` — you may be prompted for your password."
        raise '`caddy trust` failed — re-run `ecaddy setup` or run `sudo caddy trust` manually.' unless Caddy.trust
      end

      def start_service
        if Caddy.running?
          Caddy.restart_service
        else
          Caddy.start_service
        end
      end

      def print_success
        puts
        puts '  ecaddy setup complete!'
        puts
        puts '  Next steps:'
        puts '    ecaddy add myapp --port 3001 --vite-port 3050'
        puts '    # then visit https://myapp.localhost'
        puts
        puts '  Or in your Procfile.dev:'
        puts '    caddy: ecaddy run --config ./Caddyfile'
      end
    end
  end
end

# frozen_string_literal: true

require 'thor'
require_relative 'version'
require_relative 'commands/setup'
require_relative 'commands/remove'
require_relative 'commands/edit'
require_relative 'commands/list'
require_relative 'commands/up'
require_relative 'commands/down'
require_relative 'commands/status'
require_relative 'commands/doctor'
require_relative 'commands/reload'
require_relative 'commands/ensure'
require_relative 'commands/run'
require_relative 'commands/logs'
require_relative 'commands/audit'
require_relative 'commands/retrust'

module EasyCaddy
  class CLI < Thor
    def self.exit_on_failure? = true

    desc 'setup', 'One-time machine bootstrap: install Caddy, scaffold config, start service'
    def setup
      require 'tty-prompt'
      Commands::Setup.new(prompt: TTY::Prompt.new).call
    end

    desc 'remove NAME', 'Remove a site from global Caddy and delete its fragment'
    option :force, type: :boolean, default: false, aliases: '-f', desc: 'Skip confirmation'
    def remove(name)
      require 'tty-prompt'
      Commands::Remove.new(name: name, force: options[:force], prompt: TTY::Prompt.new).call
    end

    desc 'edit NAME', 'Open a site fragment in $EDITOR and reload Caddy'
    def edit(name)
      Commands::Edit.new(name: name).call
    end

    desc 'list', 'List all registered sites'
    option :format, type: :string, default: 'table', aliases: '-f', desc: 'Output format: table or json'
    def list
      Commands::List.new(format: options[:format]).call
    end

    desc 'up NAME', 'Enable a disabled site and reload Caddy'
    def up(name)
      Commands::Up.new(name: name).call
    end

    desc 'down NAME', 'Disable an enabled site and reload Caddy'
    def down(name)
      Commands::Down.new(name: name).call
    end

    desc 'status', 'Show global Caddy state and per-site health'
    def status
      Commands::Status.new.call
    end

    desc 'doctor', 'Scan for port/domain conflicts and dead upstreams'
    def doctor
      Commands::Doctor.new.call
    end

    desc 'reload', 'Validate and reload the global Caddy config'
    def reload
      Commands::Reload.new.call
    end

    desc 'ensure', 'One-shot: copy project Caddyfile into global config and exit (for scripts/CI)'
    option :config, type: :string, required: true,  aliases: '-c', desc: 'Path to project Caddyfile'
    option :site,   type: :string, required: true,  aliases: '-s', desc: 'Site name (used as fragment filename)'
    def ensure
      Commands::Ensure.new(config_path: options[:config], site: options[:site]).call
    end

    desc 'run', 'Register Caddyfile; block and unregister on shutdown (for Procfile.dev)'
    option :config, type: :string, required: true,  aliases: '-c', desc: 'Path to project Caddyfile'
    option :site,   type: :string, required: true,  aliases: '-s', desc: 'Site name (used as fragment filename)'
    def caddy_run
      Commands::Run.new(config_path: options[:config], site: options[:site]).call
    end
    map 'run' => :caddy_run

    desc 'logs', 'Tail the Caddy log files for a site'
    option :site,   type: :string,  required: true, aliases: '-s', desc: 'Site name'
    option :lines,  type: :numeric, default: 200,   aliases: '-n', desc: 'Number of lines (with --no-follow)'
    option :follow, type: :boolean, default: true, desc: 'Follow log (tail -F). Use --no-follow to print and exit.'
    def logs
      Commands::Logs.new(site: options[:site], lines: options[:lines], follow: options[:follow]).call
    end

    desc 'audit', 'Print a full system + TLS + site snapshot'
    option :site, type: :string,  aliases: '-s', desc: 'Limit to a single site'
    option :fix,  type: :boolean, default: false, desc: 'After report, prompt to apply a fix for each failing check'
    def audit
      Commands::Audit.new(site: options[:site], fix: options[:fix]).call
    end

    desc 'retrust', 'Re-trust local CA and restart Caddy to reissue certs (fixes net::ERR_CERT_DATE_INVALID)'
    def retrust
      Commands::Retrust.new.call
    end

    desc 'version', 'Print ecaddy version'
    def version
      puts "ecaddy #{EasyCaddy::VERSION}"
    end
  end
end

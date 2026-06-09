# frozen_string_literal: true

module EasyCaddy
  module Paths
    def self.root
      Pathname.new(ENV.fetch('ECADDY_HOME', File.join(Dir.home, '.config', 'caddy')))
    end

    def self.sites_dir    = root.join('sites')
    def self.disabled_dir = root.join('disabled')
    def self.registry     = root.join('ecaddy.yml')
    def self.caddyfile    = root.join('Caddyfile')
    def self.brew_caddyfile = Pathname.new('/opt/homebrew/etc/Caddyfile')

    def self.site_file(name)    = sites_dir.join("#{name}.caddy")
    def self.disabled_file(name) = disabled_dir.join("#{name}.caddy")
  end
end

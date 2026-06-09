# frozen_string_literal: true

require_relative 'lib/easy_caddy/version'

Gem::Specification.new do |spec|
  spec.name          = 'easy_caddy'
  spec.version       = EasyCaddy::VERSION
  spec.authors       = ['Pawel Niemczyk']
  spec.email         = ['pniemczyk.info@gmail.com']
  spec.summary       = 'CLI to manage a single global Caddy for multiple local Rails projects'
  spec.description   = 'ecaddy registers per-project Caddyfile fragments into a shared ' \
                       'global Caddy instance, with conflict detection, Procfile integration, ' \
                       'and one-shot machine setup.'
  spec.homepage      = 'https://github.com/pniemczyk/easy_caddy'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['source_code_uri']       = spec.homepage
  spec.metadata['changelog_uri']         = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['documentation_uri']     = 'https://pniemczyk.github.io/easy_caddy/'
  spec.metadata['bug_tracker_uri']       = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files       = Dir['lib/**/*', 'exe/*', 'README.md', 'CHANGELOG.md', 'LICENSE']
  spec.bindir      = 'exe'
  spec.executables = ['ecaddy']

  spec.add_dependency 'thor',       '~> 1.3'
  spec.add_dependency 'tty-prompt', '~> 0.23'
  spec.add_dependency 'tty-table',  '~> 0.12'

  spec.add_development_dependency 'rake',          '~> 13.0'
  spec.add_development_dependency 'rspec',         '~> 3.13'
  spec.add_development_dependency 'rubocop',       '~> 1.65'
  spec.add_development_dependency 'rubocop-rspec', '~> 3.0'
end

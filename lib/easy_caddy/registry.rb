# frozen_string_literal: true

require 'yaml'
require_relative 'paths'
require_relative 'site'

module EasyCaddy
  class Registry
    def self.load = new(Paths.registry)

    def initialize(path = Paths.registry)
      @path = path
      @data = path.exist? ? YAML.safe_load(path.read, permitted_classes: [Symbol]) || {} : {}
    end

    def all
      @data.values.map { |h| Site.from_h(h) }
    end

    def find(name)
      h = @data[name]
      Site.from_h(h) if h
    end

    def add(site)
      @data[site.name] = site.to_h
      save
    end

    def update(site)
      raise ArgumentError, "Unknown site: #{site.name}" unless @data.key?(site.name)

      @data[site.name] = site.to_h
      save
    end

    def remove(name)
      @data.delete(name)
      save
    end

    private

    def save
      @path.parent.mkpath
      @path.write(YAML.dump(@data))
    end
  end
end

# frozen_string_literal: true

module EasyCaddy
  Site = Data.define(:name, :enabled, :source_path) do
    def self.from_h(h)
      new(name: h['name'], enabled: h.fetch('enabled', true), source_path: h['source_path'])
    end

    def to_h
      { 'name' => name, 'enabled' => enabled, 'source_path' => source_path }
    end
  end
end

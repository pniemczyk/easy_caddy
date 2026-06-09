# frozen_string_literal: true

RSpec.describe EasyCaddy::Registry do
  def build_site(name)
    EasyCaddy::Site.new(name: name, enabled: true, source_path: "/projects/#{name}/Caddyfile")
  end

  subject(:registry) { described_class.load }

  describe '#add and #all' do
    it 'persists a site and reads it back' do
      registry.add(build_site('fishme'))
      expect(described_class.load.all.map(&:name)).to include('fishme')
    end
  end

  describe '#find' do
    it 'returns nil for unknown names' do
      expect(registry.find('ghost')).to be_nil
    end

    it 'returns the site when registered' do
      registry.add(build_site('fishme'))
      expect(registry.find('fishme').name).to eq('fishme')
    end
  end

  describe '#remove' do
    it 'removes the site from the registry' do
      registry.add(build_site('fishme'))
      registry.remove('fishme')
      expect(described_class.load.find('fishme')).to be_nil
    end
  end

  describe '#update' do
    it 'persists the changed enabled state' do
      registry.add(build_site('fishme'))
      updated = EasyCaddy::Site.new(name: 'fishme', enabled: false, source_path: nil)
      registry.update(updated)
      expect(described_class.load.find('fishme').enabled).to be false
    end
  end
end

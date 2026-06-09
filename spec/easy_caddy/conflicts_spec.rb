# frozen_string_literal: true

RSpec.describe EasyCaddy::Conflicts do
  FISHME_CADDY = <<~CADDY
    fishme.localhost {
      handle /vite-dev/* {
        reverse_proxy localhost:3054
      }
      reverse_proxy localhost:3104
      tls internal
    }
    vite.fishme.localhost {
      reverse_proxy localhost:3054
      tls internal
    }
  CADDY

  LETLY_CADDY = <<~CADDY
    letly.localhost {
      reverse_proxy localhost:3100
      tls internal
    }
  CADDY

  def register_site(registry, name, content)
    # Write a fragment file so enabled_site_data can read it
    EasyCaddy::Paths.sites_dir.mkpath
    EasyCaddy::Paths.site_file(name).write(content)
    registry.add(EasyCaddy::Site.new(name: name, enabled: true, source_path: nil))
  end

  describe '.check — domain collision' do
    it 'returns BLOCK when domain is already registered' do
      reg = EasyCaddy::Registry.load
      register_site(reg, 'fishme', FISHME_CADDY)

      findings = described_class.check(
        name: 'copy', content: FISHME_CADDY, registry: EasyCaddy::Registry.load
      )
      expect(findings.any? { |f| f.severity == 'BLOCK' && f.message.include?('fishme.localhost') }).to be true
    end
  end

  describe '.check — port collision' do
    it 'returns BLOCK when a port is already taken' do
      reg = EasyCaddy::Registry.load
      register_site(reg, 'fishme', FISHME_CADDY)

      findings = described_class.check(
        name: 'letly', content: FISHME_CADDY, registry: EasyCaddy::Registry.load
      )
      expect(findings.any? { |f| f.severity == 'BLOCK' && f.message.include?('3104') }).to be true
    end

    it 'passes when ports are different' do
      reg = EasyCaddy::Registry.load
      register_site(reg, 'fishme', FISHME_CADDY)

      findings = described_class.check(
        name: 'letly', content: LETLY_CADDY, registry: EasyCaddy::Registry.load
      )
      expect(findings.select { |f| f.severity == 'BLOCK' }).to be_empty
    end
  end

  describe '.check — skip_name' do
    it 'does not flag a site against itself' do
      reg = EasyCaddy::Registry.load
      register_site(reg, 'fishme', FISHME_CADDY)

      findings = described_class.check(
        name: 'fishme', content: FISHME_CADDY,
        registry: EasyCaddy::Registry.load, skip_name: 'fishme'
      )
      expect(findings.select { |f| f.severity == 'BLOCK' }).to be_empty
    end
  end

  describe '.doctor — cross-site conflicts' do
    it 'detects shared ports across registered sites' do
      reg = EasyCaddy::Registry.load
      register_site(reg, 'fishme', FISHME_CADDY)
      # Force letly to use the same port by writing a conflicting fragment
      EasyCaddy::Paths.site_file('letly').write(FISHME_CADDY)
      reg.add(EasyCaddy::Site.new(name: 'letly', enabled: true, source_path: nil))

      findings = described_class.doctor(registry: EasyCaddy::Registry.load)
      expect(findings.any? { |f| f.severity == 'BLOCK' }).to be true
    end
  end
end

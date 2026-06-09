# frozen_string_literal: true

require 'easy_caddy/commands/setup'

RSpec.describe EasyCaddy::Commands::Setup do
  let(:prompt) { instance_double('TTY::Prompt') }
  let(:setup)  { described_class.new(prompt: prompt) }

  describe '#build_trust_error' do
    it 'flags an unreachable admin endpoint and suggests a brew restart' do
      msg = setup.send(:build_trust_error, 'dial tcp [::1]:2019: connect: connection refused')

      expect(msg).to include('caddy trust` failed')
      expect(msg).to include('connection refused')
      expect(msg).to include('brew services restart caddy')
    end

    it 'suggests sudo when the trust store rejects the certificate' do
      msg = setup.send(:build_trust_error, 'permission denied installing certificate')

      expect(msg).to include('sudo caddy trust')
    end

    it 'falls back to a generic hint for unknown failures' do
      msg = setup.send(:build_trust_error, 'some other unrecognised error')

      expect(msg).to include('Re-run `ecaddy setup`')
    end
  end

  describe '#trust_ca' do
    it 'aborts with a clear message if the admin endpoint never comes up' do
      allow(EasyCaddy::Caddy).to receive(:wait_for_admin_endpoint).and_return(false)

      expect { setup.send(:trust_ca) }
        .to raise_error(/admin endpoint at localhost:2019 is not responding/i)
    end

    it 'returns silently when trust succeeds' do
      allow(EasyCaddy::Caddy).to receive(:wait_for_admin_endpoint).and_return(true)
      allow(EasyCaddy::Caddy).to receive(:trust_with_output).and_return(['ok', true])

      expect { setup.send(:trust_ca) }.not_to raise_error
    end

    it 'raises a formatted error when trust fails' do
      allow(EasyCaddy::Caddy).to receive(:wait_for_admin_endpoint).and_return(true)
      allow(EasyCaddy::Caddy).to receive(:trust_with_output)
        .and_return(['dial tcp [::1]:2019: connect: connection refused', false])

      expect { setup.send(:trust_ca) }
        .to raise_error(/caddy trust` failed.*connection refused.*brew services restart caddy/mi)
    end
  end
end

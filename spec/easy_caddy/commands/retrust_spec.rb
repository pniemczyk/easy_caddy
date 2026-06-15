# frozen_string_literal: true

require 'easy_caddy/commands/retrust'

RSpec.describe EasyCaddy::Commands::Retrust do
  subject(:retrust) { described_class.new }

  before do
    allow(EasyCaddy::Caddy).to receive(:running?).and_return(true)
    allow(EasyCaddy::Caddy).to receive(:untrust_with_output).and_return(['', true])
    allow(EasyCaddy::Caddy).to receive(:trust_with_output).and_return(['', true])
    allow(EasyCaddy::Caddy).to receive(:restart_service).and_return(true)
  end

  describe '#call' do
    it 'raises when Caddy is not running' do
      allow(EasyCaddy::Caddy).to receive(:running?).and_return(false)

      expect { retrust.call }.to raise_error(EasyCaddy::Error, /brew services start caddy/)
    end

    it 'raises when caddy untrust fails' do
      allow(EasyCaddy::Caddy).to receive(:untrust_with_output).and_return(['permission denied', false])

      expect { retrust.call }.to raise_error(EasyCaddy::Error, /caddy untrust failed.*permission denied/m)
    end

    it 'raises when caddy trust fails' do
      allow(EasyCaddy::Caddy).to receive(:trust_with_output).and_return(['connection refused', false])

      expect { retrust.call }.to raise_error(EasyCaddy::Error, /caddy trust failed.*connection refused/m)
    end

    it 'restarts Caddy after re-trusting to reissue certificates' do
      retrust.call

      expect(EasyCaddy::Caddy).to have_received(:restart_service).once
    end

    it 'raises when the restart fails' do
      allow(EasyCaddy::Caddy).to receive(:restart_service).and_return(false)

      expect { retrust.call }.to raise_error(EasyCaddy::Error, /restart failed/)
    end

    it 'prints success and does not raise when all steps succeed' do
      expect { retrust.call }.to output(/CA re-trusted and certificates reissued/).to_stdout
    end
  end
end

# frozen_string_literal: true

RSpec.describe EasyCaddy::Parser do
  SAMPLE = <<~CADDY
    fishme.localhost {
      handle /vite-dev/* {
        reverse_proxy localhost:3054
      }
      reverse_proxy localhost:3104
      tls internal

      log {
        output file /abs/log/caddy.log {
          roll_size 2mb
        }
      }
    }

    vite.fishme.localhost {
      reverse_proxy localhost:3054
      tls internal
    }
  CADDY

  describe '.parse' do
    subject(:result) { described_class.parse(SAMPLE) }

    it 'extracts all domains' do
      expect(result.domains).to contain_exactly('fishme.localhost', 'vite.fishme.localhost')
    end

    it 'extracts unique ports' do
      expect(result.ports).to contain_exactly(3054, 3104)
    end

    it 'extracts log file paths' do
      expect(result.log_paths).to contain_exactly('/abs/log/caddy.log')
    end
  end

  describe '.parse with multiple log outputs' do
    let(:content) do
      <<~CADDY
        fishme.localhost {
          log { output file /log/access.log }
          log { output file /log/error.log }
        }
      CADDY
    end

    it 'returns all unique log paths' do
      result = described_class.parse(content)
      expect(result.log_paths).to contain_exactly('/log/access.log', '/log/error.log')
    end
  end

  describe '.parse with no log directives' do
    let(:content) { "fishme.localhost {\n  reverse_proxy localhost:3000\n}\n" }

    it 'returns an empty log_paths array' do
      expect(described_class.parse(content).log_paths).to be_empty
    end
  end

  describe '.infer_name' do
    it 'returns the stem of the first non-vite domain' do
      expect(described_class.infer_name(SAMPLE)).to eq('fishme')
    end

    it 'returns nil when no localhost domain is found' do
      expect(described_class.infer_name('# empty')).to be_nil
    end
  end
end

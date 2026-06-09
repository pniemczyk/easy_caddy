# frozen_string_literal: true

# Expose private methods via a test double that includes the module.
class RegisterHelpersHost
  include EasyCaddy::Commands::RegisterHelpers
  public :absolutize_log_paths, :ensure_log_mode, :ensure_log_dirs, :probe_tls, :tls_handshake_ok?
end

RSpec.describe EasyCaddy::Commands::RegisterHelpers do
  subject(:host) { RegisterHelpersHost.new }

  describe '#absolutize_log_paths' do
    let(:base) { '/projects/fishme' }

    it 'rewrites a relative log path to an absolute one' do
      input = 'output file log/caddy.log {'
      result = host.absolutize_log_paths(input, base)
      expect(result).to eq('output file /projects/fishme/log/caddy.log {')
    end

    it 'leaves an already-absolute path unchanged' do
      input = 'output file /var/log/caddy.log {'
      result = host.absolutize_log_paths(input, base)
      expect(result).to eq('output file /var/log/caddy.log {')
    end

    it 'handles multiple log output directives in one file' do
      input = <<~CADDY
        output file log/access.log {
          roll_size 2mb
        }
        output file log/error.log {
          roll_size 1mb
        }
      CADDY
      result = host.absolutize_log_paths(input, base)
      expect(result).to include('output file /projects/fishme/log/access.log')
      expect(result).to include('output file /projects/fishme/log/error.log')
    end

    it 'does not alter lines without output file directives' do
      input = "reverse_proxy localhost:3104\ntls internal\n"
      expect(host.absolutize_log_paths(input, base)).to eq(input)
    end
  end

  describe '#ensure_log_mode' do
    it 'wraps a bare output file directive in a block with mode 0660' do
      result = host.ensure_log_mode('output file /var/log/caddy.log')
      expect(result).to eq("output file /var/log/caddy.log {\n    mode 0660\n  }")
    end

    it 'inserts mode 0660 as the first line of an existing block' do
      input  = "output file /var/log/caddy.log {\n  roll_size 2mb\n}"
      result = host.ensure_log_mode(input)
      expect(result).to eq("output file /var/log/caddy.log {\n    mode 0660\n  roll_size 2mb\n}")
    end

    it 'leaves a block that already sets mode untouched' do
      input = "output file /var/log/caddy.log {\n  mode 0640\n}"
      expect(host.ensure_log_mode(input)).to eq(input)
    end

    it 'does not alter content without an output file directive' do
      input = "reverse_proxy localhost:3000\ntls internal\n"
      expect(host.ensure_log_mode(input)).to eq(input)
    end
  end

  describe '#ensure_log_dirs' do
    it 'creates the parent directory of each log path in the content' do
      log_dir = File.join(@ecaddy_home, 'myapp', 'log')
      content = "output file #{log_dir}/caddy.log {"
      host.ensure_log_dirs(content)
      expect(File.directory?(log_dir)).to be true
    end

    it 'does nothing when there are no log directives' do
      expect { host.ensure_log_dirs("reverse_proxy localhost:3000\n") }.not_to raise_error
    end
  end

  describe '#probe_tls' do
    it 'prints a warning for domains that fail the handshake' do
      allow(host).to receive(:tls_handshake_ok?).and_return(false)
      expect { host.probe_tls(['fishme.localhost']) }.to output(/WARN.*fishme\.localhost/).to_stderr
    end

    it 'does not print anything for domains that succeed' do
      allow(host).to receive(:tls_handshake_ok?).and_return(true)
      expect { host.probe_tls(['fishme.localhost']) }.not_to output.to_stderr
    end
  end

  describe '#tls_handshake_ok?' do
    it 'returns false when connection is refused' do
      allow(TCPSocket).to receive(:new).and_raise(Errno::ECONNREFUSED.new('connection refused'))
      expect(host.tls_handshake_ok?('fishme.localhost')).to be false
    end
  end
end

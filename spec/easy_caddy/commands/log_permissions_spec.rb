# frozen_string_literal: true

require 'fileutils'

# Minimal harness so we can drive register_helpers' private methods directly.
class LogPermissionsHarness
  include EasyCaddy::Commands::RegisterHelpers
  public :ensure_log_dirs, :ensure_log_writable, :build_log_permission_error
end

RSpec.describe EasyCaddy::Commands::RegisterHelpers do
  let(:harness) { LogPermissionsHarness.new }
  let(:log_dir) { File.join(@ecaddy_home, 'mylog') }
  let(:log_file) { File.join(log_dir, 'caddy.log') }

  describe '#ensure_log_writable' do
    it 'creates the parent directory and touches the file' do
      harness.ensure_log_writable(log_file)

      expect(File).to exist(log_file)
      expect(File).to be_writable(log_file)
    end

    it 'raises a clear error when the file is not writable' do
      FileUtils.mkdir_p(log_dir)
      FileUtils.touch(log_file)
      File.chmod(0o400, log_file)

      expect { harness.ensure_log_writable(log_file) }
        .to raise_error(EasyCaddy::Error, /Cannot write to Caddy log file.*sudo chmod 0660/m)
    ensure
      File.chmod(0o600, log_file) if File.exist?(log_file)
    end
  end

  describe '#ensure_log_dirs' do
    it 'pre-creates every log file declared in the fragment' do
      content = <<~CADDY
        myapp.localhost {
          log {
            output file #{log_file}
          }
        }
      CADDY

      harness.ensure_log_dirs(content)

      expect(File).to exist(log_file)
    end
  end
end

RSpec.describe EasyCaddy::Caddy do
  describe '.translate_validate_error' do
    it 'extracts the underlying Error: line and adds a chmod hint when the failure is a log permission denied' do
      output = <<~OUT
        {"level":"info","msg":"using config from file"}
        {"level":"warn","msg":"Caddyfile input is not formatted"}
        Error: setting up custom log 'log1': opening log writer: open /Users/bob/proj/log/caddy.log: permission denied
      OUT

      msg = described_class.translate_validate_error(output)

      expect(msg).to include('log file not writable')
      expect(msg).to include('/Users/bob/proj/log/caddy.log')
      expect(msg).to include('sudo chmod 0660 /Users/bob/proj/log/caddy.log')
      expect(msg).to include('ecaddy audit --fix')
    end

    it 'falls back to the Error: line for other failures' do
      output = <<~OUT
        {"level":"info","msg":"using config from file"}
        Error: adapting config using caddyfile: unknown directive 'pizza'
      OUT

      msg = described_class.translate_validate_error(output)

      expect(msg).to include('Caddy config invalid')
      expect(msg).to include("unknown directive 'pizza'")
    end

    it 'returns the raw output when no Error: line is present' do
      output = "garbled output\nno error line\n"

      msg = described_class.translate_validate_error(output)

      expect(msg).to include('garbled output')
    end
  end
end

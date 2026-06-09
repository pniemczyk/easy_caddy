# frozen_string_literal: true

RSpec.describe EasyCaddy::Commands::Logs do
  let(:site_name) { 'fishme' }
  let(:log_path)  { File.join(@ecaddy_home, 'log', 'caddy.log') }

  let(:fragment_content) do
    <<~CADDY
      fishme.localhost {
        reverse_proxy localhost:3104
        log { output file #{log_path} }
      }
    CADDY
  end

  def write_enabled_fragment(content = fragment_content)
    EasyCaddy::Paths.sites_dir.mkpath
    EasyCaddy::Paths.site_file(site_name).write(content)
  end

  def register_site(enabled: true)
    registry = EasyCaddy::Registry.load
    site     = EasyCaddy::Site.new(name: site_name, enabled: enabled, source_path: '/src/Caddyfile')
    registry.add(site)
  end

  describe '#call' do
    context 'when site is not in registry' do
      it 'aborts with a message' do
        expect do
          described_class.new(site: site_name, lines: 50, follow: false).call
        end.to raise_error(SystemExit)
      end
    end

    context 'when site has no log directives' do
      before do
        register_site
        write_enabled_fragment("fishme.localhost { reverse_proxy localhost:3104 }\n")
      end

      it 'prints guidance and returns' do
        expect do
          described_class.new(site: site_name, lines: 50, follow: false).call
        end.to output(/No 'output file'/).to_stdout
      end
    end

    context 'when log file does not exist yet' do
      before do
        register_site
        write_enabled_fragment
      end

      it 'prints a note and returns (no log files to tail)' do
        expect do
          described_class.new(site: site_name, lines: 50, follow: false).call
        end.to output(/not yet created|No log files exist/).to_stdout
      end
    end

    context 'when log file exists' do
      before do
        register_site
        write_enabled_fragment
        FileUtils.mkdir_p(File.dirname(log_path))
        File.write(log_path, "line1\nline2\n")
      end

      it 'execs tail with follow flag' do
        cmd = described_class.new(site: site_name, lines: 50, follow: true)
        expect(cmd).to receive(:exec).with('tail', '-F', log_path)
        cmd.call
      end

      it 'execs tail with -n flag when not following' do
        cmd = described_class.new(site: site_name, lines: 20, follow: false)
        expect(cmd).to receive(:exec).with('tail', '-n', '20', log_path)
        cmd.call
      end
    end

    context 'when site is disabled' do
      before do
        register_site(enabled: false)
        EasyCaddy::Paths.disabled_dir.mkpath
        FileUtils.mkdir_p(File.dirname(log_path))
        File.write(log_path, "line1\n")
        EasyCaddy::Paths.disabled_file(site_name).write(fragment_content)
      end

      it 'reads the disabled fragment' do
        cmd = described_class.new(site: site_name, lines: 50, follow: false)
        expect(cmd).to receive(:exec).with('tail', '-n', '50', log_path)
        cmd.call
      end
    end
  end
end

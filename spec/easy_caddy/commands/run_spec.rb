# frozen_string_literal: true

RSpec.describe EasyCaddy::Commands::Run do
  let(:home)   { @ecaddy_home }
  let(:config) { File.join(home, 'fishme.caddy') }

  before do
    FileUtils.mkdir_p(EasyCaddy::Paths.sites_dir.to_s)

    File.write(EasyCaddy::Paths.caddyfile.to_s, <<~CADDY)
      {
        admin localhost:2019
      }
      import sites/*.caddy
    CADDY

    File.write(config, <<~CADDY)
      fishme.localhost {
        reverse_proxy localhost:3104
        tls internal
      }
    CADDY

    allow(EasyCaddy::Caddy).to receive(:validate!).and_return(true)
    allow(EasyCaddy::Caddy).to receive(:reload).and_return(true)
  end

  it 'registers the fragment on start and removes it on SIGTERM' do
    pid = fork do
      ENV['ECADDY_HOME'] = home
      EasyCaddy::Commands::Run.new(config_path: config, site: 'fishme').call
    end

    sleep 0.3
    expect(EasyCaddy::Paths.site_file('fishme')).to exist

    Process.kill('TERM', pid)
    Process.wait(pid)

    expect(EasyCaddy::Paths.site_file('fishme')).not_to exist
  end
end

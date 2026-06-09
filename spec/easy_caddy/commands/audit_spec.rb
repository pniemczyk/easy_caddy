# frozen_string_literal: true

require 'tty-prompt'

RSpec.describe EasyCaddy::Commands::Audit do
  def stub_externals(installed: true, brew_pid: 12_345, proc_pid: nil, ca_trusted: true)
    allow(EasyCaddy::Caddy).to receive(:installed?).and_return(installed)
    allow(EasyCaddy::Caddy).to receive(:brew_service_pid).and_return(brew_pid)
    allow(EasyCaddy::Caddy).to receive(:process_pid).and_return(proc_pid)
    allow_any_instance_of(described_class).to receive(:caddy_ca_trusted?).and_return(ca_trusted)
    allow_any_instance_of(described_class).to receive(:browser_trusts?).and_return(ca_trusted)
    allow_any_instance_of(described_class).to receive(:port_open?).and_return(false)
    allow_any_instance_of(described_class).to receive(:check_port).and_return(nil)
    allow_any_instance_of(described_class).to receive(:tls_probe)
      .and_return([true, 'cert CN=Caddy Local Authority'])
    allow_any_instance_of(described_class).to receive(:tcp_open?).and_return(true)
    allow_any_instance_of(described_class).to receive(:`).and_return("v2.9.1\n")
  end

  def stub_caddyfile
    EasyCaddy::Paths.caddyfile.parent.mkpath
    EasyCaddy::Paths.caddyfile.write("{ admin localhost:2019 }\nimport sites/*.caddy\n")
    allow(EasyCaddy::Paths).to receive(:brew_caddyfile).and_return(
      instance_double(Pathname, symlink?: true, exist?: true,
                                readlink: EasyCaddy::Paths.caddyfile)
    )
  end

  def write_enabled_fragment(name, content)
    EasyCaddy::Paths.sites_dir.mkpath
    EasyCaddy::Paths.site_file(name).write(content)
  end

  let(:fragment_content) do
    <<~CADDY
      fishme.localhost {
        reverse_proxy localhost:3104
        tls internal
        log { output file /tmp/fishme.log }
      }
    CADDY
  end

  before do
    stub_externals
    stub_caddyfile
  end

  describe '#call with no sites' do
    it 'prints system and TLS sections without crashing' do
      expect { described_class.new.call }.to output(/SYSTEM/).to_stdout
    end
  end

  describe '#call with a registered site' do
    before do
      registry = EasyCaddy::Registry.load
      registry.add(EasyCaddy::Site.new(name: 'fishme', enabled: true, source_path: '/src/Caddyfile'))
      write_enabled_fragment('fishme', fragment_content)
    end

    it 'prints the site name' do
      expect { described_class.new.call }.to output(/fishme/).to_stdout
    end

    it 'prints a TLS result for each domain' do
      expect { described_class.new.call }.to output(/fishme\.localhost/).to_stdout
    end
  end

  describe 'inline hints' do
    before do
      stub_externals(brew_pid: nil, proc_pid: nil)
      stub_caddyfile
    end

    it 'shows a hint when Caddy is not running' do
      expect { described_class.new.call }.to output(/hint:.*brew services start caddy/).to_stdout
    end

    it 'collects a fix when Caddy is not running' do
      audit = described_class.new
      audit.call
      fixes = audit.instance_variable_get(:@fixes)
      expect(fixes).not_to be_empty
      expect(fixes.first.command).to include('brew services start caddy')
    end
  end

  describe 'brew vs process detector' do
    before { stub_caddyfile }

    context 'when brew service is down but a caddy process is running' do
      before { stub_externals(brew_pid: nil, proc_pid: 99_999) }

      it 'shows a warning about the external process' do
        expect { described_class.new.call }.to output(/Caddy process 99999 is running/).to_stdout
      end

      it 'collects a fix to stop and restart via brew' do
        audit = described_class.new
        audit.call
        fix = audit.instance_variable_get(:@fixes).find { |f| f.command.include?('pkill') }
        expect(fix).not_to be_nil
      end
    end
  end

  describe 'TLS hint matching' do
    subject(:audit) { described_class.new }

    it 'returns a reload hint for internal error / alert 80' do
      hint, fix = audit.send(:tls_hint_and_fix, 'tlsv1 alert internal error (SSL alert number 80)')
      expect(hint).to match(/stale/)
      expect(fix[:command]).to include('caddy reload')
    end

    it 'returns a caddy trust hint for unknown CA' do
      hint, fix = audit.send(:tls_hint_and_fix, 'SSL_connect returned=1 errno=0 state=error: certificate verify failed')
      expect(hint).to match(/not trusted/)
      expect(fix[:command]).to eq('caddy trust')
    end

    it 'returns a start hint for connection refused' do
      hint, fix = audit.send(:tls_hint_and_fix, 'connection refused on :443 (Caddy not running or not bound)')
      expect(hint).to match(/not listening/)
      expect(fix[:command]).to include('brew services start caddy')
    end

    it 'returns nil hint/fix for unknown errors' do
      hint, fix = audit.send(:tls_hint_and_fix, 'some weird SSL error')
      expect(hint).to be_nil
      expect(fix).to be_nil
    end

    it 'attaches a verify lambda when a domain is provided' do
      _hint, fix = audit.send(:tls_hint_and_fix, 'tlsv1 alert internal error', 'fishme.localhost')
      expect(fix[:verify]).to be_a(Proc)
    end

    it 'leaves verify nil when no domain is provided' do
      _hint, fix = audit.send(:tls_hint_and_fix, 'tlsv1 alert internal error')
      expect(fix[:verify]).to be_nil
    end
  end

  describe 'browser-trust check' do
    before do
      registry = EasyCaddy::Registry.load
      registry.add(EasyCaddy::Site.new(name: 'fishme', enabled: true, source_path: '/src/Caddyfile'))
      write_enabled_fragment('fishme', fragment_content)
    end

    context 'when browser does not trust the cert' do
      before do
        allow_any_instance_of(described_class).to receive(:browser_trusts?).and_return(false)
      end

      it 'reports browser-trust failure' do
        expect { described_class.new.call }.to output(/browser-trust ✗/).to_stdout
      end

      it 'reports the ERR_CERT_AUTHORITY_INVALID message' do
        expect { described_class.new.call }.to output(/ERR_CERT_AUTHORITY_INVALID/).to_stdout
      end

      it 'collects a fix whose next_fix uses sudo caddy trust' do
        audit = described_class.new
        audit.call
        fix = audit.instance_variable_get(:@fixes).find { |f| f.command == 'caddy trust' }
        expect(fix).not_to be_nil
        expect(fix.next_fix.command).to eq('sudo caddy trust')
      end

      it 'attaches a verifier that calls browser_trusts? for the domain' do
        audit = described_class.new
        audit.call
        fix = audit.instance_variable_get(:@fixes).find { |f| f.command == 'caddy trust' }
        expect(audit).to receive(:browser_trusts?).with('fishme.localhost').and_return(true)
        expect(fix.verify.call).to be true
      end
    end

    context 'when browser trusts the cert' do
      before do
        allow_any_instance_of(described_class).to receive(:browser_trusts?).and_return(true)
      end

      it 'reports browser-trusted green' do
        expect { described_class.new.call }.to output(/browser-trusted ✓/).to_stdout
      end
    end
  end

  describe '#call filtered by site' do
    it 'reports when the requested site is not registered' do
      expect { described_class.new(site: 'unknown').call }.to output(/No site 'unknown'/).to_stdout
    end
  end

  describe '--fix mode' do
    def make_fix(label: 'test issue', description: 'test fix', command: 'true',
                 verify: nil, escalation: nil, next_fix: nil)
      EasyCaddy::Commands::Audit::Fix.new(
        label: label, description: description, command: command,
        verify: verify, escalation: escalation, next_fix: next_fix
      )
    end

    before do
      stub_externals(brew_pid: nil, proc_pid: nil)
      stub_caddyfile
      allow_any_instance_of(described_class).to receive(:sleep)
    end

    it 'does not prompt when fix: false (default)' do
      expect(TTY::Prompt).not_to receive(:new)
      described_class.new(fix: false).call
    end

    it 'prompts for each collected fix when fix: true' do
      prompt = instance_double(TTY::Prompt)
      allow(TTY::Prompt).to receive(:new).and_return(prompt)
      allow(prompt).to receive(:yes?).and_return(false)

      described_class.new(fix: true).call

      expect(prompt).to have_received(:yes?).at_least(:once)
    end

    it 'runs the fix command when user answers yes' do
      prompt = instance_double(TTY::Prompt)
      allow(TTY::Prompt).to receive(:new).and_return(prompt)
      allow(prompt).to receive(:yes?).and_return(true)

      audit = described_class.new(fix: true)
      expect(audit).to receive(:system).at_least(:once).and_return(true)
      audit.call
    end

    context 'when verifier reports success after fix' do
      it 'prints "applied and verified"' do
        prompt = instance_double(TTY::Prompt)
        allow(TTY::Prompt).to receive(:new).and_return(prompt)
        allow(prompt).to receive(:yes?).and_return(true)

        audit = described_class.new(fix: true)
        allow(audit).to receive(:system).and_return(true)
        # calls: print_service_status → pre-check in run_fix → verify after apply
        allow(EasyCaddy::Caddy).to receive(:brew_service_pid).and_return(nil, nil, 12_345)

        expect { audit.call }.to output(/applied and verified/).to_stdout
      end
    end

    context 'when verifier still reports failure after fix' do
      it 'prints "still present" and the escalation hint' do
        prompt = instance_double(TTY::Prompt)
        allow(TTY::Prompt).to receive(:new).and_return(prompt)
        allow(prompt).to receive(:yes?).and_return(true)

        audit = described_class.new(fix: true)
        allow(audit).to receive(:system).and_return(true)
        allow(EasyCaddy::Caddy).to receive(:brew_service_pid).and_return(nil)

        expect { audit.call }.to output(/still present/).to_stdout
        expect { audit.call }.to output(/brew services info caddy/).to_stdout
      end
    end

    context 'when fix has no verifier attached' do
      it 'prints plain "applied" without a verify step' do
        prompt = instance_double(TTY::Prompt)
        allow(TTY::Prompt).to receive(:new).and_return(prompt)
        allow(prompt).to receive(:yes?).and_return(true)

        audit = described_class.new(fix: true)
        audit.instance_variable_set(:@fixes, [make_fix(command: 'true')])
        allow(audit).to receive(:system).with('true').and_return(true)

        expect { audit.send(:run_fixes) }.to output(/✓.*applied/).to_stdout
      end
    end

    context 'chained next_fix' do
      let(:prompt) { instance_double(TTY::Prompt) }

      before do
        allow(TTY::Prompt).to receive(:new).and_return(prompt)
      end

      it 'chains to next_fix when the primary verifier still fails' do
        next_calls = 0
        next_fix = make_fix(label: 'escalated fix', command: 'sudo thing',
                            verify: -> { (next_calls += 1) > 1 })
        fix = make_fix(command: 'thing', verify: -> { false },
                       escalation: 'needs sudo', next_fix: next_fix)

        audit = described_class.new(fix: true)
        audit.instance_variable_set(:@fixes, [fix])
        allow(audit).to receive(:system).and_return(true)
        allow(prompt).to receive(:yes?).and_return(true, true)

        expect { audit.send(:run_fixes) }.to output(/applied and verified/).to_stdout
      end

      it 'does not prompt next_fix when the primary verifies' do
        fix = make_fix(command: 'thing', verify: -> { true },
                       next_fix: make_fix(label: 'should not appear', command: 'sudo thing'))

        audit = described_class.new(fix: true)
        audit.instance_variable_set(:@fixes, [fix])
        allow(prompt).to receive(:yes?).and_return(true)

        expect { audit.send(:run_fixes) }.to output(/already resolved/).to_stdout
        expect(prompt).not_to have_received(:yes?)
      end

      it 'skips a fix whose condition is pre-resolved' do
        fix = make_fix(label: 'already fine', verify: -> { true })

        audit = described_class.new(fix: true)
        audit.instance_variable_set(:@fixes, [fix])
        allow(prompt).to receive(:yes?)

        expect { audit.send(:run_fixes) }.to output(/already resolved/).to_stdout
        expect(prompt).not_to have_received(:yes?)
      end

      it 'dedups identical commands across fixes in the same session' do
        shared_cmd = 'brew services restart caddy'
        fix1 = make_fix(label: 'port 443', command: shared_cmd,
                        verify: -> { false }, escalation: nil)
        fix2 = make_fix(label: 'port 80', command: shared_cmd,
                        verify: -> { false })

        audit = described_class.new(fix: true)
        audit.instance_variable_set(:@fixes, [fix1, fix2])
        allow(audit).to receive(:system).once.and_return(true)
        allow(prompt).to receive(:yes?).and_return(true, true)

        expect { audit.send(:run_fixes) }.to output(/already ran.*session/).to_stdout
      end

      it 'does not run next_fix when the user declines the next_fix prompt' do
        next_fix = make_fix(label: 'escalated', command: 'sudo thing')
        fix = make_fix(command: 'thing', verify: -> { false },
                       escalation: 'needs sudo', next_fix: next_fix)

        audit = described_class.new(fix: true)
        audit.instance_variable_set(:@fixes, [fix])
        allow(audit).to receive(:system).with('thing').and_return(true)
        allow(prompt).to receive(:yes?).and_return(true, false)

        expect(audit).not_to receive(:system).with('sudo thing')
        audit.send(:run_fixes)
      end
    end
  end
end

# ecaddy

[![Gem Version](https://badge.fury.io/rb/easy_caddy.svg)](https://rubygems.org/gems/easy_caddy)
[![Docs](https://img.shields.io/badge/docs-pniemczyk.github.io%2Feasy__caddy-blue)](https://pniemczyk.github.io/easy_caddy/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Changelog](https://img.shields.io/badge/changelog-CHANGELOG.md-orange)](CHANGELOG.md)

**[📖 Documentation](https://pniemczyk.github.io/easy_caddy/)** &nbsp;|&nbsp; **[GitHub](https://github.com/pniemczyk/easy_caddy)** &nbsp;|&nbsp; **[Changelog](CHANGELOG.md)**

One global [Caddy](https://caddyserver.com/) for all your local Rails projects.

Instead of fighting port conflicts from multiple Caddy processes, `ecaddy` manages a single shared Caddy instance. Each project keeps its own `Caddyfile` — `ecaddy` copies it in and out of the global config on demand.

## How it works

```
Browser
  │
  ▼
Caddy  (~/.config/caddy/Caddyfile)
  │         imports sites/*.caddy
  ├── fishme.localhost   → localhost:3104
  ├── letly.localhost    → localhost:3100
  └── traiderb.localhost → localhost:3106
```

Each Rails project has its own `Caddyfile`. When you start the project, `ecaddy` copies it into `~/.config/caddy/sites/<name>.caddy` and reloads the global Caddy. When you stop, it removes the fragment and reloads again.

## Installation

```bash
gem install easy_caddy
ecaddy setup
```

`ecaddy setup` is a one-time bootstrap that:

1. Installs Caddy via Homebrew if not already present
2. Scaffolds `~/.config/caddy/{sites,disabled}/`
3. Writes the global `Caddyfile` (with `import sites/*.caddy`)
4. Symlinks it into `/opt/homebrew/etc/Caddyfile` so `brew services` picks it up
5. Runs `caddy trust` to install the local CA in your system keychain (makes `https://*.localhost` green in browsers)
6. Starts Caddy as a `brew services` background service

Run `ecaddy setup` again at any time — every step is idempotent.

### The `--site` option

Every `ecaddy` command that registers or references a project uses a **site name** — a short identifier you choose, e.g. `fishme`. This name:

- Determines the fragment filename: `~/.config/caddy/sites/fishme.caddy`
- Is used by `up`, `down`, `edit`, `remove` to target the right project
- Should be unique across all your local projects

The name is **not** read from the Caddyfile — you always supply it explicitly with `--site fishme` (short: `-s fishme`). This keeps `ecaddy` compatible with any Caddyfile content.

## Project setup

Each project needs two things: a `Caddyfile` and a Procfile line.

### 1. Write your project Caddyfile

Put a `Caddyfile` in your project root. Write it however you need — `ecaddy` treats it as read-only source. One automatic transform is applied on copy: relative `output file` log paths are rewritten to absolute paths so Caddy (running as a background service with no relation to your project directory) can actually write the log files.

```caddy
# Caddyfile (in your Rails project root)

fishme.localhost {
  handle /vite-dev/* {
    reverse_proxy localhost:3054
  }

  reverse_proxy localhost:3104
  tls internal

  log {
    level INFO
    output file log/caddy.log {
      roll_size 2mb
      roll_keep 5
      roll_keep_for 48h
    }
  }
}

vite.fishme.localhost {
  reverse_proxy localhost:3054
  tls internal
}
```

Pick unique ports across your projects. Common pattern:

| Project  | App port | Vite port |
|----------|----------|-----------|
| fishme   | 3104     | 3054      |
| letly    | 3100     | 3050      |
| traiderb | 3106     | 3056      |

### 2. Add a Procfile line

```procfile
# Procfile.dev

web:   bin/rails server -p 3104
js:    yarn dev
caddy: ecaddy run --config ./Caddyfile --site fishme
```

When foreman (or overmind) starts, `ecaddy run` copies your `Caddyfile` into the global config and reloads Caddy. When you press `Ctrl-C`, it removes the fragment and reloads again — the domain disappears cleanly.

### 3. Allow `.localhost` in Rails

```ruby
# config/environments/development.rb

config.hosts << /.*\.localhost/
```

### 4. Start your project

```bash
bin/dev
```

Visit `https://fishme.localhost` — done.

## Commands

### `ecaddy setup`

One-time machine bootstrap. Install Caddy, scaffold the global config, trust the local CA, start the brew service.

```bash
ecaddy setup
```

---

### `ecaddy run`

Register a project Caddyfile, block, and unregister on shutdown. Use in `Procfile.dev`.

```bash
ecaddy run --config ./Caddyfile --site fishme
ecaddy run -c ./Caddyfile -s fishme
```

On `SIGTERM` or `SIGINT`, the fragment is removed and Caddy is reloaded before the process exits.

Relative `output file` log paths in the Caddyfile are automatically rewritten to absolute paths (resolved from the directory of `--config`) before the fragment is installed.

---

### `ecaddy ensure`

One-shot variant of `run`. Copies the Caddyfile, reloads Caddy, exits immediately. The site stays registered until you run `ecaddy down` or `ecaddy remove`.

```bash
ecaddy ensure --config ./Caddyfile --site fishme
```

Useful in CI or shell scripts where you want Caddy configured but don't need a foreground process.

---

### `ecaddy list`

Show all registered sites.

```bash
ecaddy list
ecaddy list --format json
```

```
┌──────────┬────────┬──────────────────────────────────────────────┬────────────┬──────────────────────────┐
│ Name     │ Status │ Domains                                      │ Ports      │ Source                   │
├──────────┼────────┼──────────────────────────────────────────────┼────────────┼──────────────────────────┤
│ fishme   │ up     │ fishme.localhost, vite.fishme.localhost       │ 3054, 3104 │ /projects/fishme/Caddyfile │
│ letly    │ down   │ letly.localhost, vite.letly.localhost         │ 3050, 3100 │ /projects/letly/Caddyfile  │
└──────────┴────────┴──────────────────────────────────────────────┴────────────┴──────────────────────────┘
```

---

### `ecaddy up NAME` / `ecaddy down NAME`

Enable or disable a registered site without removing it.

```bash
ecaddy down fishme   # moves sites/fishme.caddy → disabled/fishme.caddy, reloads
ecaddy up fishme     # moves disabled/fishme.caddy → sites/fishme.caddy, reloads
```

---

### `ecaddy status`

Show global Caddy state and per-site health (whether the upstream app is actually running).

```bash
ecaddy status
```

```
  Caddy service: running
  Config:        /Users/you/.config/caddy/Caddyfile

  fishme               up
    fragment: /Users/you/.config/caddy/sites/fishme.caddy
    source:   /projects/fishme/Caddyfile
  letly                up (app not running)
    fragment: /Users/you/.config/caddy/sites/letly.caddy
    source:   /projects/letly/Caddyfile
```

---

### `ecaddy doctor`

Scan all registered sites for port/domain conflicts and dead upstreams.

```bash
ecaddy doctor
```

Exits `0` if all clear or only INFO findings. Exits `1` on any BLOCK.

| Severity | Meaning |
|----------|---------|
| `BLOCK`  | Two sites share a port or domain — one will fail |
| `WARN`   | A port is bound by an unexpected process |
| `INFO`   | Upstream not listening (app not started) |

---

### `ecaddy audit`

Full system + TLS audit with optional fixes. Where `doctor` checks the registry,
`audit` also probes the live Caddy service, the brew-service state, a TLS handshake
per domain, and the system-keychain trust state.

```bash
ecaddy audit                # report-only
ecaddy audit --fix          # prompt to run each suggested fix
ecaddy audit --site fishme  # limit to one site
```

With `--fix`, `audit` walks each finding, prints the proposed command, asks for
confirmation, runs it, and re-verifies — chaining to a fallback fix when the first
doesn't resolve it (e.g. `caddy trust` → `sudo caddy trust`). It also flags leaf
certs outside their validity window as `ERR_CERT_DATE_INVALID` (fix: restart →
`ecaddy retrust`), and for a root-owned, unwritable log file it offers a choice —
keep as-is, take ownership (`sudo chown`), or delete.

---

### `ecaddy edit NAME`

Open a site's fragment in `$EDITOR`. Caddy is validated and reloaded after you save.

```bash
ecaddy edit fishme
```

This edits the copy in `~/.config/caddy/sites/fishme.caddy`, not your project source. Re-run `ecaddy run` (or `ecaddy ensure`) to sync from your project `Caddyfile` again.

---

### `ecaddy logs --site NAME`

Tail a site's Caddy log files. `ecaddy` reads the fragment, extracts every
`output file PATH` directive, and shells out to `tail` on them.

```bash
ecaddy logs --site fishme               # tail -F (follow)
ecaddy logs --site fishme --lines 100   # last 100 lines
ecaddy logs --site fishme --no-follow   # print and exit
```

Works for both enabled and disabled sites. If the Caddyfile has no `output file`
directives, `ecaddy` prints guidance and exits.

---

### `ecaddy remove NAME`

Remove a site's fragment and registry entry entirely.

```bash
ecaddy remove fishme
ecaddy remove fishme --force   # skip confirmation
```

---

### `ecaddy reload`

Validate the global config and reload Caddy.

```bash
ecaddy reload
```

---

### `ecaddy retrust`

Re-trust the local Caddy CA _and_ reissue certificates. Run this when your browser
shows `net::ERR_CERT_DATE_INVALID` or `NET::ERR_CERT_AUTHORITY_INVALID` on a
`*.localhost` site — the cached leaf cert has expired, or the local CA is missing
from the system keychain.

```bash
ecaddy retrust
```

Runs `caddy untrust` (removes the old cert) then `caddy trust` (re-installs it),
then restarts Caddy so it reissues the short-lived `*.localhost` leaf certs. macOS
prompts for your password for each keychain operation. Afterwards, fully reload your
browser (or quit and reopen it) to drop the stale cached certificate.

---

### `ecaddy version`

```bash
ecaddy version
# ecaddy 0.1.4
```

## Global config layout

```
~/.config/caddy/
  Caddyfile           # global root: { admin ... } + import sites/*.caddy
  ecaddy.yml          # registry: name → { enabled, source_path }
  sites/
    fishme.caddy      # enabled fragments — loaded by Caddy
    letly.caddy
  disabled/
    traiderb.caddy    # disabled fragments — preserved, not loaded
```

The global `Caddyfile` is also symlinked at `/opt/homebrew/etc/Caddyfile` so `brew services start caddy` picks it up automatically.

## Conflict detection

Before registering any Caddyfile, `ecaddy` parses it and checks:

- **Domain collision** — same `*.localhost` domain already registered by another enabled site → BLOCK
- **Port collision** — same `reverse_proxy localhost:PORT` already in use by another site → BLOCK

These checks run on `ecaddy run`, `ecaddy ensure`, and `ecaddy up`. Run `ecaddy doctor` at any time for a full cross-site audit.

## Environment variable

Set `ECADDY_HOME` to override the config root (defaults to `~/.config/caddy`). Useful for testing:

```bash
ECADDY_HOME=/tmp/ecaddy_test ecaddy list
```

## Development

```bash
bin/setup              # bundle install
bundle exec rspec      # run the full spec suite
bundle exec rubocop    # lint
bin/console            # IRB session with easy_caddy preloaded
```

To run the CLI against the local source without installing the gem:

```bash
bundle exec exe/ecaddy <command>
```

Cutting a release: bump `EasyCaddy::VERSION` in `lib/easy_caddy/version.rb`, add a `CHANGELOG.md` entry, commit, then `bundle exec rake release` — that tags the commit and pushes the gem to RubyGems (requires `gem signin` first).

## Contributing

Bug reports and pull requests are welcome at <https://github.com/pniemczyk/easy_caddy>. Please run the spec suite and `rubocop` before opening a PR.

## License

Released under the [MIT License](LICENSE).

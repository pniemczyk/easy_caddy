# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] — 2026-06-09

### Added

- `EasyCaddy::Error` exception class for user-facing failures. `exe/ecaddy`
  now rescues it and prints a clean one-line message to stderr (exit 1),
  replacing Ruby's default backtrace dump on expected errors.
- Registered fragments now have `output file` directives rewritten to
  include `mode 0660` so log files (and rolled successors) stay
  group-writable — Caddy runs as root to bind `:80`/`:443`, but
  `caddy validate` / `caddy reload` run as the unprivileged user and need
  to open them.
- `ecaddy audit` now reports each declared log file as writable, missing,
  or root-locked, with an interactive `--fix` that escalates to
  `sudo chmod` when needed.

### Fixed

- `ecaddy setup` now starts the Caddy brew service **before** running
  `caddy trust`, fixing a `connection refused` failure on fresh installs
  (the local-CA fetch requires the admin endpoint at `localhost:2019` to
  be running). Setup also polls the admin endpoint for up to 10 s before
  attempting trust.
- `caddy trust` failures now surface the underlying output plus an
  actionable hint (brew restart, `sudo caddy trust`, or re-run `setup`)
  instead of a generic message.
- `ecaddy run` / `ecaddy ensure` now pre-create each log file declared
  in the fragment and fail fast with a `sudo chmod` hint when the file
  or its directory is owned by another user (typically left over from a
  previous `sudo` run). The opaque `permission denied` from Caddy's
  config validator is now translated into a one-line, actionable error.

## [0.1.0] — 2026-06-09

### Added

- Initial public release.
- Thor CLI `ecaddy` with commands: `setup`, `run`, `ensure`, `up`, `down`,
  `list`, `edit`, `logs`, `remove`, `reload`, `status`, `doctor`, `audit`.
- Single-source-of-truth path management via `EasyCaddy::Paths` — every
  filesystem path derives from the `ECADDY_HOME` env var (defaults to
  `~/.config/caddy`), keeping the tool fully redirectable for tests and
  multi-user setups.
- YAML registry (`ecaddy.yml`) tracking each site by name, enabled state,
  and source Caddyfile path.
- Conflict detection: `*.localhost` domain collisions and
  `reverse_proxy localhost:PORT` port collisions across registered
  fragments, plus TCP probing of upstream ports via `ecaddy doctor`.
- Automatic rewrite of relative `output file` log paths to absolute paths
  on registration, so Caddy (running as a background service detached from
  the project directory) can write log files correctly.
- One-shot machine bootstrap (`ecaddy setup`): Homebrew install of Caddy,
  global Caddyfile scaffold, `caddy trust` for local-CA HTTPS, and
  `brew services` start. Idempotent — safe to re-run.
- Foreground `ecaddy run --site NAME` mode: registers the fragment, traps
  `SIGTERM`/`SIGINT`, and unregisters on exit — designed to drop into a
  Procfile alongside the Rails server.

[0.1.2]: https://github.com/pniemczyk/easy_caddy/releases/tag/v0.1.2
[0.1.0]: https://github.com/pniemczyk/easy_caddy/releases/tag/v0.1.0

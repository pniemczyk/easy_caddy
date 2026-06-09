# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.0]: https://github.com/pniemczyk/easy_caddy/releases/tag/v0.1.0

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Run all specs
bundle exec rspec

# Run a single spec file
bundle exec rspec spec/easy_caddy/conflicts_spec.rb

# Run a single example by line number
bundle exec rspec spec/easy_caddy/conflicts_spec.rb:34

# Run the CLI from the repo root (no gem install required)
bundle exec exe/ecaddy <command>

# Run the CLI against a temp config dir (safe, won't touch ~/.config/caddy)
ECADDY_HOME=/tmp/ecaddy_test bundle exec exe/ecaddy list

# Lint
bundle exec rubocop

# Build the gem
gem build easy_caddy.gemspec
```

## Architecture

`ecaddy` is a Thor CLI gem. The entry point is `exe/ecaddy` → `EasyCaddy::CLI` (Thor subclass in `lib/easy_caddy/cli.rb`). Each CLI command delegates immediately to a dedicated command object in `lib/easy_caddy/commands/`.

### Core data flow

1. **`Paths`** (`paths.rb`) — single source of all filesystem paths. Every path derives from `ECADDY_HOME` env var (defaults to `~/.config/caddy`). All specs set `ECADDY_HOME` to a tmpdir so the real config is never touched.

2. **`Registry`** (`registry.rb`) — reads/writes `ecaddy.yml` (a YAML hash keyed by site name). Stores only `{ name, enabled, source_path }` — no Caddyfile content, no port/domain data.

3. **`Site`** (`site.rb`) — a `Data` value object with `name`, `enabled`, `source_path`. Immutable; pass a new instance to `registry.update`.

4. **`Parser`** (`parser.rb`) — minimal regex-based Caddyfile parser. Extracts `*.localhost` domains and `reverse_proxy localhost:PORT` ports from fragment content. Used by `Conflicts` and `List` — not used during registration itself.

5. **`Conflicts`** (`conflicts.rb`) — runs domain/port collision checks. `Conflicts.check` is called before registering a fragment (reads existing enabled fragment files via `Paths.site_file`). `Conflicts.doctor` scans all registered sites cross-wise and TCP-probes each upstream port.

6. **`Caddy`** (`caddy.rb`) — thin wrapper around the `caddy` binary and `brew services`. `validate!` and `reload` are no-ops when the global Caddyfile doesn't exist yet (safe to run before `ecaddy setup`).

### Registration flow (`run` / `ensure`)

Both share `Commands::RegisterHelpers`:

1. Validate the source config file exists.
2. Run `Conflicts.check` against the registry (abort on BLOCK).
3. `absolutize_log_paths` rewrites relative `output file` log paths to absolute ones (resolved from the Caddyfile's directory), then writes the result to `~/.config/caddy/sites/<name>.caddy`.
4. Upsert the registry entry.
5. `Caddy.validate!` + `Caddy.reload`.

`run` then blocks with a signal trap; `SIGTERM`/`SIGINT` calls `unregister` (deletes the fragment, reloads Caddy) and exits 0.

### `up` / `down`

Move the fragment between `sites/` and `disabled/` (via `Pathname#rename`) and update `enabled` in the registry. Caddy is reloaded after each move. `Parser` is not involved — the fragment file is moved as-is.

### Thor reserved word workaround

`run` is a Thor reserved method name. The actual method is named `caddy_run` and mapped via `map 'run' => :caddy_run` in `cli.rb`.

### Testing isolation

Every spec runs with a fresh tmpdir as `ECADDY_HOME` (set in `spec/spec_helper.rb` `before`/`after` hooks). Specs that exercise `Conflicts` must manually write fragment files to `Paths.sites_dir` because `Conflicts` reads actual files, not in-memory data. `run_spec.rb` forks a child process to test signal handling.

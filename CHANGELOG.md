# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.1] - 2026-05-08

### Fixed

- macOS portability: `_lib_with_lock` no longer depends on `flock(1)`,
  which is util-linux only and not present on macOS by default. Locking
  is now done with an atomic `mkdir`-based mutex on the lockfile path,
  with stale-lock reaping after 60 seconds.
- bash 3.2 portability: `_cmd_add` and `_cmd_tag` array dereferences
  switched to `${arr[@]+"${arr[@]}"}` so empty arrays under `set -u`
  do not trigger "unbound variable" on macOS system bash.
- `cc-harness doctor`: `TERM supports 256color` and `fzf available` are
  now truly optional (reported but never increment the failure count).
  Headless CI runners with `TERM=dumb` no longer flag a doctor failure.

## [0.1.0] - 2026-05-08

### Added

- Single-file bash launcher at `bin/cc-harness` with full subcommand surface:
  `attach`, `new`, `kill`, `list`, `add`, `remove`, `rename`, `tag`, `untag`,
  `status`, `doctor`, `logs`, `which`, `completion`, `version`.
- XDG-aware path resolution (`CCH_HOME` -> `XDG_CONFIG_HOME` -> legacy
  `~/cc-harness/`) with one-time auto-migration from the legacy location and
  a stderr notice gated by a state-dir marker.
- Extended `projects.conf` schema: `label = path [| flags] [#tag1 #tag2]`.
- Per-project flag overrides via `--flags '...'`. Tag filtering on `new`,
  `kill`, `list`, `status`.
- Multi-instance per project: `cc-harness new <label> --fresh` spawns
  `<label>-2`, `<label>-3`, ...; `--switch` errors if no window exists.
- Independent client view: `cc-harness attach <label>` opens a grouped tmux
  session pinned to a single project, so a second terminal can sit on a
  different window without affecting the first.
- Self-healing menu: `Ctrl-b 0` rebound to recreate the menu window if
  killed; `prefix + N` opens the project picker from any window. Stale
  windows whose pane PID is dead are renamed `[dead] <label>` on next attach.
- Validators for label/tag/path with the documented exit-code surface
  (1 generic, 2 usage, 3 config, 4 tmux, 5 deps).
- `flock`-based mutex around config-mutating operations.
- `-v` verbose mode logs to `$XDG_STATE_HOME/cc-harness/cc-harness.log` with
  1 MiB rotation (3 generations).
- Preflight checks on every spawn: claude binary present, tmux >= 3.0.
- Bash, zsh, and fish completions emitted by `cc-harness completion <shell>`.
- man(1) page source at `man/cc-harness.1.md` (pandoc -> roff at build).
- Per-subcommand `--help` with examples.
- bats-core test suite (44 tests across 9 files): unit + integration,
  bats v1.11.1 pinned as a submodule, isolated tmux sockets per test.
- Makefile targets: `completions`, `man`, `install`, `uninstall`, `test`,
  `lint`, `fmt`, `fmt-check`, `dist`, `deb`, `rpm`, `clean`.
- `install.sh` curl-bash entry point with sha256 verification.
- shellcheck-clean script and test helper.

### Fixed

- Menu window vanishing was permanent: once `Ctrl-b &` killed it, no
  invocation recreated it. `cc-harness attach` now self-heals window 0.

[Unreleased]: https://github.com/alejandro-soto-franco/cc-harness/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/alejandro-soto-franco/cc-harness/releases/tag/v0.1.1
[0.1.0]: https://github.com/alejandro-soto-franco/cc-harness/releases/tag/v0.1.0

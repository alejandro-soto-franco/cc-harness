# cc-harness

Multi-session Claude Code launcher backed by tmux.

`cc-harness` runs many Claude Code sessions in parallel inside one tmux
session, with one named window per project. A persistent menu window at
index 0 is the control loop: pick a project to spawn, kill, or edit. Sessions
survive terminal disconnects because tmux keeps them alive.

## Install

```bash
# Universal: curl-bash installer (verifies sha256 from GitHub release)
curl -fsSL https://raw.githubusercontent.com/alejandro-soto-franco/cc-harness/main/install.sh | bash

# User-local (no sudo)
curl -fsSL https://raw.githubusercontent.com/alejandro-soto-franco/cc-harness/main/install.sh | bash -s -- --user

# Source build
git clone https://github.com/alejandro-soto-franco/cc-harness
cd cc-harness && git submodule update --init --recursive
make install            # PREFIX=/usr/local by default
```

Distro packages (Homebrew, Fedora Copr, AUR, .deb/.rpm) ship from the same
GitHub release tarball. See `packaging/` for the recipes.

## Quick start

```bash
cc-harness add polybius ~/Polybius          # one-time
cc-harness                                   # attach the menu
cc-harness new polybius                      # spawn or switch
```

`Ctrl-b 0` jumps back to the menu (and self-heals if it was killed).
`Ctrl-b N` opens the project picker from any window. `Ctrl-b d` detaches; the
session keeps running.

## Configuration

`$XDG_CONFIG_HOME/cc-harness/projects.conf` (typically
`~/.config/cc-harness/projects.conf`). One line per project:

```
LABEL = PATH [| FLAGS] [#TAG1 #TAG2 ...]
```

Example:

```
polybius     = ~/Polybius | --model opus     #live #trading
pmp          = ~/pmp                          #math #writing
fleming      = ~/fleming                      #math #writing #paper
```

The legacy `~/cc-harness/projects.conf` is auto-migrated to XDG on first run;
the original is left in place until you remove it.

## Tags and filters

```bash
cc-harness list --tag math          # filter to math projects
cc-harness list --tags              # discover unique tags + counts
cc-harness kill --tag scratch       # bulk-kill all tagged "scratch"
cc-harness new fleming --fresh      # spawn a sibling: fleming-2
```

## Commands

| Command | Purpose |
|---------|---------|
| `cc-harness` | Attach (create session if needed) |
| `cc-harness new [<label>] [--fresh\|--switch]` | Spawn or switch |
| `cc-harness attach <label>` | Per-terminal pinned view (grouped session) |
| `cc-harness kill [--all] [--tag T] [--dry-run]` | Kill window(s) |
| `cc-harness list [--tag T] [--tags]` | Project table or tag index |
| `cc-harness add <label> <path> [--flags '...'] [--tag t]` | Append project |
| `cc-harness remove <label>` | Drop project |
| `cc-harness rename <old> <new>` | Rename config + live window |
| `cc-harness tag <label> +foo -bar`, `untag <label>` | Edit tags |
| `cc-harness status [--json]` | Active sessions + harness info |
| `cc-harness doctor` | Env checks; exit code = failure count |
| `cc-harness logs <label>` | Last 3000 lines from a pane |
| `cc-harness which <label>` | Resolved path of a label |
| `cc-harness completion <bash\|zsh\|fish>` | Emit completion script |
| `cc-harness <subcmd> --help` | Per-subcommand help with examples |

Full reference: `man cc-harness`.

## Tmux keybindings

| Chord | Action |
|-------|--------|
| `Ctrl-b 0` | Menu window (self-heals if killed) |
| `Ctrl-b N` | Project picker from any window |
| `Ctrl-b 1`..`9` | Jump to window N |
| `Ctrl-b w` | Interactive window list |
| `Ctrl-b d` | Detach; session keeps running |
| `Ctrl-b ,` | Rename current window |
| `Ctrl-b &` | Kill current window |

## Environment variables

| Name | Purpose | Default |
|------|---------|---------|
| `CCH_HOME` | Override config + state dir | unset (use XDG) |
| `CCH_FLAGS` | Flags appended to claude on every spawn | `--dangerously-skip-permissions` |
| `CCH_CLAUDE` | Path to claude binary | `claude` (on PATH) |
| `CCH_SESSION` | tmux session name | `cc-harness` |
| `CCH_VERBOSE`, `CCH_QUIET` | Equivalent to `-v` / `-q` | `0` |
| `NO_COLOR` | Disable ANSI color output (de facto standard) | unset |

## Troubleshooting

`cc-harness doctor` checks tmux >= 3.0, claude on PATH, projects.conf
parseable, every project path exists, terminal capability, and fzf presence.
Exit code is the number of failed checks.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Tests run via `make test`; lint with
`make lint`. Bash 3.2 portability is a project rule (macOS system bash is
3.2). Run `make fmt-check` before opening a PR.

## License

MIT. See [LICENSE](LICENSE).

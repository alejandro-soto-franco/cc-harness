# cc-harness

Multi-session Claude Code launcher backed by tmux.

`cc-harness` is a single-file bash CLI that runs many Claude Code sessions
in parallel inside one tmux session, with one named window per project. A
persistent menu window at index 0 acts as the control loop: you pick a
project to spawn, switch to, kill, or edit. tmux keeps everything alive
across SSH disconnects, terminal crashes, and lid closes, so a forgotten
claude session is exactly where you left it on the next attach.

## Why this exists

Running half a dozen Claude Code sessions in plain terminals means burned
windows, lost scrollback, and "wait, was that the polybius shell or the
fleming one?" tmux already solves the persistence problem; this tool adds
the project list, the picker, the per-project working directory, and a few
small ergonomics: tag-based filters, per-project flag overrides, a
self-healing menu, and `[dead]` flagging when a claude crashes so the
window does not silently disappear.

It is intentionally small: one bash file, one tmux dependency, one
optional `fzf` for nicer pickers. No daemon, no telemetry, no auto-update.

## Install

### curl-bash (universal)

```bash
curl -fsSL https://raw.githubusercontent.com/alejandro-soto-franco/cc-harness/main/install.sh | bash
```

The installer downloads the latest GitHub release tarball, verifies its
SHA-256, and runs `make install` into `/usr/local` if writable, otherwise
`~/.local`.

User-local install (no sudo, picks `~/.local` regardless):

```bash
curl -fsSL https://raw.githubusercontent.com/alejandro-soto-franco/cc-harness/main/install.sh | bash -s -- --user
```

Pin a specific version:

```bash
CC_HARNESS_VERSION=v0.1.0 curl -fsSL https://raw.githubusercontent.com/alejandro-soto-franco/cc-harness/main/install.sh | bash
```

Uninstall (delegates to `cc-harness uninstall` when present):

```bash
curl -fsSL https://raw.githubusercontent.com/alejandro-soto-franco/cc-harness/main/install.sh | bash -s -- --uninstall
```

### Homebrew (macOS, Linuxbrew)

A formula lives in `packaging/homebrew/cc-harness.rb` and is mirrored to a
separate tap repo:

```bash
brew install alejandro-soto-franco/cc-harness/cc-harness
```

### Fedora / RHEL via Copr

```bash
sudo dnf copr enable alejandro-soto-franco/cc-harness
sudo dnf install cc-harness
```

### Arch via AUR

```bash
yay -S cc-harness
```

### Debian / Ubuntu

Download the `.deb` from the GitHub Releases page and install with apt:

```bash
sudo apt install ./cc-harness_0.1.0_all.deb
```

### Source build

```bash
git clone https://github.com/alejandro-soto-franco/cc-harness
cd cc-harness
git submodule update --init --recursive
make install              # PREFIX=/usr/local by default
```

Override the prefix:

```bash
make install PREFIX="$HOME/.local"
```

## Quick start

```bash
cc-harness add polybius ~/Polybius          # one-time, registers a project
cc-harness                                  # attach the menu (or create it)
cc-harness new polybius                     # spawn or switch
```

Inside the harness, `Ctrl-b 0` jumps to the menu (and self-heals if it was
killed). `Ctrl-b N` opens the picker from any window. `Ctrl-b d` detaches;
the session keeps running.

## Configuration

The project list lives at `$XDG_CONFIG_HOME/cc-harness/projects.conf`,
which on most systems means `~/.config/cc-harness/projects.conf`. Schema,
one line per project:

```
LABEL = PATH [| FLAGS] [#TAG1 #TAG2 ...]
```

Worked example:

```
polybius     = ~/Polybius | --model opus     #live #trading #rust
pmp          = ~/pmp                         #math #writing
fleming      = ~/fleming                     #math #writing #paper
home         = ~                             #scratch
```

Rules:

- `LABEL` matches `^[a-zA-Z0-9_-]+$`, length 1 to 32.
- `PATH` is expanded at parse time (`~` becomes `$HOME`); the file stays
  portable across users.
- `FLAGS`, when present, is appended to the claude invocation only for
  that project, after the global `CCH_FLAGS` value.
- `TAGS` use `#name` syntax. Tag format: `^[a-zA-Z0-9_-]+$`, length 1 to
  24. Multiple tags are space-separated. Order does not matter. Filters
  are case-insensitive.
- Comments: lines starting with `#` are ignored. Comments at end of a
  config line are not currently supported (a trailing `#tag` is read as a
  tag, by design).

If you previously used `cc-harness` from before the XDG move, your old
`~/cc-harness/projects.conf` is auto-migrated on first run. The original
file is left in place; `cc-harness doctor` will mention it once the new
location is populated, and you can remove the legacy directory yourself
when you have confirmed everything works.

You can override the lookup chain with `CCH_HOME=/path/to/dir`, in which
case `cc-harness` reads `$CCH_HOME/projects.conf` and stores state under
the same directory.

## Tags and filters

Tagging is the workhorse for navigating a many-project setup.

```bash
cc-harness list --tag math          # show only #math projects
cc-harness list --tags              # discover unique tags with counts
cc-harness kill --tag scratch       # bulk-kill all tagged "scratch"
cc-harness new fleming --fresh      # spawn a sibling: fleming-2
```

Tag editing happens through the `tag` and `untag` subcommands, which
preserve the rest of the line:

```bash
cc-harness tag polybius +rust -experimental    # add #rust, remove #experimental
cc-harness untag polybius                      # strip all tags
```

Discovery via shell completion: when `--tag <TAB>` is requested, the
completion script reads `cc-harness list --tags` and offers the live tag
set.

## Multi-instance per project

By default, `cc-harness new <label>` switches to the existing window when
one is open and spawns a new one when it is not. Two flags override that
behavior:

| Invocation | Behavior |
|------------|----------|
| `cc-harness new <label>` | Spawn or switch (script-safe default). |
| `cc-harness new <label> --fresh` | Always spawn a sibling: `<label>-2`, then `<label>-3`, and so on. |
| `cc-harness new <label> --switch` | Only switch. Errors with exit 4 if no window exists. |
| `cc-harness new` (no label) | Interactive picker; on collision, prompts `[s]witch / [f]resh / [c]ancel`. |

Sibling windows show up under their base label in `list`, `status`, and
`kill`, so tagging the parent project automatically applies to siblings.

## Independent per-terminal views

Plain tmux gives every connected client the same active-window pointer,
so opening two terminals into the harness shows the same claude in both.
That is wrong for the common case of pinning one terminal to a single
project and using another terminal as your "scratch" view.

`cc-harness attach <label>` solves this with a grouped tmux session.
The grouped session shares the underlying window set, so any spawn made
in either view is visible to the other, but each view has its own current
window. Two examples:

Terminal A:

```bash
cc-harness attach polybius
```

Terminal B:

```bash
cc-harness attach pmp
```

Both stay on their respective projects regardless of what the other does.
Spawning a new project from either is visible to both.

## Robustness

A few small things make the harness less brittle than a hand-rolled tmux
session:

- **Menu auto-respawn.** Window 0 named `menu` is the control loop. If
  somebody (or something) closes that window with `Ctrl-b &`, the next
  attach recreates it.
- **`prefix + 0` rebind.** The chord is rebound at session bootstrap so
  it spawns the menu when missing instead of failing with "no such
  window".
- **`prefix + N` picker.** From any window, `Ctrl-b N` (capital) opens
  the project picker without going back to the menu first.
- **Stale-window detection.** When a claude crashes, tmux keeps the pane
  open (we set `remain-on-exit on` so users can read the traceback). The
  next attach scans for windows whose pane PID is dead and renames them
  `[dead] <label>`.
- **Preflight.** Before spawning, `cc-harness` checks that the claude
  binary is on PATH and that tmux is at least 3.0. Missing dependencies
  fail fast with exit 5 and a clear message.
- **Lockfile.** All config-mutating subcommands (`add`, `remove`,
  `rename`, `tag`, `untag`) hold a `flock` on
  `$XDG_RUNTIME_DIR/cc-harness-$UID.lock` so concurrent invocations cannot
  corrupt `projects.conf`.
- **Verbose log.** Pass `-v` to write a rotating log to
  `$XDG_STATE_HOME/cc-harness/cc-harness.log` (1 MiB rotation, 3
  generations).
- **`Ctrl-C` in the menu loop.** SIGINT is trapped so a stray Ctrl-C
  inside the picker redraws the menu instead of dropping you to a broken
  shell.

## Subcommands

| Command | Purpose |
|---------|---------|
| `cc-harness` | Attach (creating the session if needed). |
| `cc-harness new [<label>] [--fresh\|--switch]` | Spawn or switch. |
| `cc-harness attach [<label>]` | Attach the harness, or open a per-label client view. |
| `cc-harness kill [--all] [--tag T] [--dry-run]` | Kill a window or bulk-kill by tag. |
| `cc-harness list [--tag T] [--tags]` | Project table or unique-tag index. |
| `cc-harness add <label> <path> [--flags '...'] [--tag t]...` | Append a project. |
| `cc-harness remove <label> [--dry-run]` | Drop a project. |
| `cc-harness rename <old> <new>` | Rename config entry plus the live tmux window. |
| `cc-harness tag <label> +foo -bar` | Edit tags. |
| `cc-harness untag <label>` | Strip all tags. |
| `cc-harness status [--json] [--tag T]` | Active sessions, claude binary, host uptime, harness version. |
| `cc-harness doctor` | Run environment checks; exit code is the failure count. |
| `cc-harness logs <label>` | Print up to 3000 lines of pane scrollback. |
| `cc-harness which <label>` | Print the resolved filesystem path. |
| `cc-harness completion <bash\|zsh\|fish>` | Emit completion script. |
| `cc-harness --version`, `cc-harness version` | Print version with optional git SHA. |
| `cc-harness <subcmd> --help` | Per-subcommand help with examples. |

Full reference: `man cc-harness`.

## Tmux keybindings

The harness session is created with these defaults; existing tmux
configuration is otherwise untouched. The prefix is whatever you have
configured in `~/.tmux.conf` (default `Ctrl-b`).

| Chord | Action |
|-------|--------|
| `Ctrl-b 0` | Menu window (self-heals if killed). |
| `Ctrl-b N` | Project picker, from any window. |
| `Ctrl-b 1` to `Ctrl-b 9` | Jump to window N. |
| `Ctrl-b w` | Interactive window list. |
| `Ctrl-b d` | Detach; session keeps running. |
| `Ctrl-b ,` | Rename current window. |
| `Ctrl-b &` | Kill current window (closes that claude). |

## Environment variables

| Name | Purpose | Default |
|------|---------|---------|
| `CCH_HOME` | Override config and state directory. | unset (use XDG) |
| `CCH_FLAGS` | Flags appended to claude on every spawn. | `--dangerously-skip-permissions` |
| `CCH_CLAUDE` | Path to the claude binary. | `claude` (on PATH) |
| `CCH_SESSION` | tmux session name. | `cc-harness` |
| `CCH_VERBOSE`, `CCH_QUIET` | Equivalent to passing `-v` or `-q`. | `0` |
| `NO_COLOR` | Disable ANSI color output (de facto standard). | unset |
| `TMUX_FLAGS` | Prepended to every internal tmux invocation; used by the test suite to target an isolated server (`-L SOCKET`). | empty |

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | success |
| 1 | generic error |
| 2 | usage error (unknown subcmd, bad flag) |
| 3 | config error (parse, validation) |
| 4 | tmux not running, session/window not found |
| 5 | external dependency missing (claude, tmux) |

## Troubleshooting

`cc-harness doctor` checks tmux 3.0+, claude on PATH, projects.conf
parseable, every project path exists, terminal capability, and fzf
presence. The exit code equals the number of failed checks. Sample
output:

```
cc-harness doctor:
  OK tmux installed
  OK tmux >= 3.0
  OK claude binary on PATH
  OK projects.conf parseable
  OK every project path exists
  OK TERM supports 256color
  OK fzf available (optional)
```

Common situations:

- **`claude binary not found on PATH`**: install Claude Code, or set
  `CCH_CLAUDE=/path/to/claude`.
- **`requires tmux >= 3.0 (found 2.x)`**: upgrade tmux. RHEL 7 / Debian
  10 ship 2.x; brew or copr packages have current builds.
- **menu window keeps dying**: that was the v0 bug. Update to v0.1.0+.
- **two terminals fight over the same window**: use
  `cc-harness attach <label>` for an independent client view instead of
  bare `cc-harness`.

## Bash 3.2 portability

The script targets bash 3.2+ because macOS still ships 3.2 by default.
That means: no associative arrays, no `mapfile`, no `${var,,}`, no
`[[ -v var ]]`, no `wait -n`, no `coproc`. CI runs the test suite on
ubuntu-latest with system bash 5.x, on macos-latest with system bash
3.2, and on macos-latest with brew-installed bash 5.x, so portability
regressions surface immediately.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for dev setup, the bash 3.2 rule
set, the PR checklist, and the DCO sign-off requirement.

Quick loop:

```bash
git clone https://github.com/alejandro-soto-franco/cc-harness
cd cc-harness
git submodule update --init --recursive
make test          # bats suite (44 tests)
make lint          # shellcheck
make fmt-check     # shfmt diff
```

## Security

If you find a security issue, please email the maintainer rather than
filing a public issue. Details in [SECURITY.md](SECURITY.md). The
`install.sh` curl-bash flow is the most security-relevant surface; it
verifies SHA-256 on the downloaded tarball before extraction.

## License

MIT. See [LICENSE](LICENSE).

Copyright (c) 2026 Alejandro Soto Franco.

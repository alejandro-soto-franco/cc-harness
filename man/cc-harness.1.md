% CC-HARNESS(1) cc-harness 0.1.0 | User Commands
% Alejandro Soto Franco
% 2026

# NAME

cc-harness - multi-session Claude Code launcher backed by tmux

# SYNOPSIS

**cc-harness** [*-v* | *-q*] [*--no-color*] [*COMMAND*] [*ARGS*]

# DESCRIPTION

**cc-harness** runs multiple Claude Code sessions in parallel inside a single
tmux session, with one named tmux window per project. A persistent menu window
at index 0 acts as the control loop: pick a project to spawn, kill, or edit
the project list. Sessions survive terminal disconnects because tmux keeps
them alive.

The configuration lives in *projects.conf*; each line names a project label,
its working directory, and (optionally) extra flags to pass to claude and a
set of tags for filtering.

# COMMANDS

**attach** [*LABEL*]
:   Attach (or create) the harness session. With *LABEL*, open an isolated
    client view focused on that project via a grouped tmux session, so that
    a second terminal can pin a different project.

**new** [*LABEL*] [*--fresh* | *--switch*]
:   Spawn a new claude session, or switch to an existing one. *--fresh*
    always spawns a sibling window with auto-suffix (*LABEL-2*, *LABEL-3*,
    ...). *--switch* errors if no window for *LABEL* exists.

**kill** [*--all*] [*--tag* *T*] [*--dry-run*]
:   Pick a window to kill, or kill in bulk by tag. *--dry-run* prints what
    would be killed without doing it.

**list** [*--tag* *T*] [*--tags*]
:   Print the projects table with an EXISTS column, optionally filtered by
    tag. *--tags* prints unique tags with counts instead.

**add** *LABEL* *PATH* [*--flags* *'STR'*] [*--tag* *TAG*]... [*--dry-run*]
:   Append a row to projects.conf. Validates label, path, and uniqueness.

**remove** *LABEL* [*--dry-run*]
:   Delete the row for *LABEL*.

**rename** *OLD* *NEW*
:   Rename the projects.conf entry and the live tmux window in one shot.

**tag** *LABEL* +*TAG* -*TAG* ...
:   Add or remove tags on a project.

**untag** *LABEL*
:   Strip all tags from *LABEL*.

**status** [*--json*] [*--tag* *T*]
:   Print harness version, claude binary, host uptime, and active sessions.

**doctor**
:   Run environment checks. Exit code = number of failed checks.

**logs** *LABEL*
:   Print up to 3000 lines of pane scrollback for *LABEL*.

**which** *LABEL*
:   Print the resolved (~ expanded) filesystem path for *LABEL*.

**completion** *bash* | *zsh* | *fish*
:   Emit a completion script to stdout.

**version**, **--version**, **-V**
:   Print version with optional git short SHA.

**--help**, **-h**
:   Print top-level help. Use *cc-harness COMMAND --help* for per-subcommand
    pages with examples.

# CONFIGURATION

The projects file lives at *$XDG_CONFIG_HOME/cc-harness/projects.conf*
(typically *~/.config/cc-harness/projects.conf*). One line per project:

```
LABEL = PATH [| FLAGS] [#TAG1 #TAG2 ...]
```

The *FLAGS* segment is appended to claude's invocation only for that project.
Tags filter *list*, *kill*, and *status* views; tag matching is
case-insensitive.

The legacy location *~/cc-harness/projects.conf* is auto-migrated on first
run; the original file is left in place until the user removes it.

# ENVIRONMENT

**CCH_HOME**
:   Override the config + state directory entirely.

**CCH_FLAGS**
:   Flags passed to claude on every spawn (default
    *--dangerously-skip-permissions*).

**CCH_CLAUDE**
:   Path to the claude binary (default *claude* on PATH).

**CCH_SESSION**
:   tmux session name (default *cc-harness*).

**CCH_VERBOSE**, **CCH_QUIET**
:   Equivalent to passing *-v* / *-q*.

**NO_COLOR**
:   Disable ANSI color output. Honored as a de facto standard.

**TMUX_FLAGS**
:   Prepended to every internal tmux invocation. Used by the test suite to
    target an isolated server (*-L SOCKET*).

# FILES

*$XDG_CONFIG_HOME/cc-harness/projects.conf*
:   Project list.

*$XDG_STATE_HOME/cc-harness/cc-harness.log*
:   Trace log when *-v* is set. Rotated at 1 MiB (3 generations).

*$XDG_RUNTIME_DIR/cc-harness-$UID.lock*
:   Ephemeral mutex for config-mutating subcommands.

# EXIT STATUS

| Code | Meaning |
|------|---------|
| 0    | success |
| 1    | generic error |
| 2    | usage error |
| 3    | config error |
| 4    | tmux not running, session/window not found |
| 5    | external dependency missing (claude, tmux) |

# EXAMPLES

Spawn (or switch to) a project:

```
cc-harness new polybius
```

Open two separate per-project views in two terminals:

```
# terminal 1
cc-harness attach polybius

# terminal 2
cc-harness attach pmp
```

Tag-filtered bulk kill:

```
cc-harness kill --tag scratch --dry-run
cc-harness kill --tag scratch --all
```

# SEE ALSO

**tmux**(1), **fzf**(1)

# AUTHOR

Alejandro Soto Franco <sotofranco.eng@gmail.com>

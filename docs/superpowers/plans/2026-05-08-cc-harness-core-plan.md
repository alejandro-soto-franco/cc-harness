# cc-harness v0.1.0 — Core Implementation Plan (Plan 1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a hardened, fully-featured single-file bash CLI at `bin/cc-harness` with a bats-core test suite, implementing every behavior in the spec sections §2–§5, §7.1–7.3, §8.2. End state: `bin/cc-harness` works as a personal tool, every spec'd subcommand exists, today's menu-window-vanished bug is regression-tested, the script is shellcheck-clean.

**Architecture:** Single bash file structured as `_cmd_<name>` dispatch handlers calling `_lib_<name>` shared helpers (path resolution, config parsing, validation, errors, logging, locking, preflight). Tests use a per-socket tmux server (`tmux -L`) and a stubbed `claude` binary so spawned windows don't actually start Claude. TDD throughout — every behavior change lands behind a test.

**Tech Stack:** bash 3.2+, tmux 3.0+, bats-core (git submodule), shellcheck, shfmt. No runtime deps beyond bash + tmux + optional fzf.

**Spec reference:** `docs/superpowers/specs/2026-05-08-cc-harness-oss-readiness-design.md`

**Scope boundary:** Plan 2 covers Makefile, `install.sh`, completions packaging, man page, Homebrew/Copr/AUR/deb/rpm, GitHub Actions CI, README and other OSS-hygiene files. Plan 1 produces a working tool you can install via `cp bin/cc-harness ~/.local/bin/` and use; Plan 2 produces the public distribution.

---

## Phase A — Scaffolding and the today-failure-mode regression

### Task 1: Repo layout, LICENSE, move script, projects.conf.example

**Files:**
- Create: `LICENSE`
- Create: `projects.conf.example`
- Move: `~/cc-harness/cc-harness` → `bin/cc-harness`
- Modify: `bin/cc-harness` (add SPDX header)

- [ ] **Step 1: Create LICENSE (MIT)**

```
MIT License

Copyright (c) 2026 Alejandro Soto Franco

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Move existing script into `bin/`**

Run: `mkdir -p bin && mv cc-harness bin/cc-harness && chmod +x bin/cc-harness`

- [ ] **Step 3: Add SPDX header to `bin/cc-harness`**

Replace the first two lines:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# cc-harness — multi-session Claude Code launcher
# https://github.com/alejandro-soto-franco/cc-harness
```

- [ ] **Step 4: Create `projects.conf.example`**

```
# cc-harness projects — one per line, "label = path [| flags] [#tag1 #tag2]"
# Lines starting with # are comments. ~ expands to $HOME.
# All suffixes (| flags, #tags) are optional.

example      = ~/code/example
docs         = ~/Documents | --model opus     #writing
scratch      = ~                                #scratch
```

- [ ] **Step 5: Re-point user's daily-driver symlink**

Run: `ln -sf "$HOME/cc-harness/bin/cc-harness" "$HOME/.local/bin/cc-harness"`
Expected: `cc-harness --help` continues to work for the user.

- [ ] **Step 6: Commit**

```bash
git add LICENSE projects.conf.example bin/cc-harness
git commit -m "feat: relocate script to bin/, add LICENSE and projects.conf.example"
```

---

### Task 2: bats-core submodule, test helper, claude stub

**Files:**
- Create: `tests/bats/` (submodule)
- Create: `tests/test_helper.bash`
- Create: `tests/fixtures/claude-stub.sh`
- Create: `tests/fixtures/projects.conf.basic`
- Create: `tests/fixtures/projects.conf.tagged`
- Create: `tests/fixtures/projects.conf.malformed`

- [ ] **Step 1: Add bats-core as submodule pinned to v1.11.0**

```bash
git submodule add -b v1.11.0 https://github.com/bats-core/bats-core tests/bats
git submodule update --init --recursive
```

- [ ] **Step 2: Write `tests/test_helper.bash`**

```bash
#!/usr/bin/env bash
# Common bats-core test helpers for cc-harness.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CCH_BIN="$REPO_ROOT/bin/cc-harness"
FIXTURES="$REPO_ROOT/tests/fixtures"
BATS_BIN="$REPO_ROOT/tests/bats/bin/bats"

setup_test_env() {
    # Per-test fake $HOME under $BATS_TEST_TMPDIR.
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_STATE_HOME="$HOME/.local/state"
    export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/run"
    mkdir -p "$XDG_RUNTIME_DIR"

    # Per-test tmux socket so parallel tests don't collide.
    export CCH_TMUX_SOCKET="cch-test-$BATS_TEST_NUMBER-$$"
    export TMUX_TEST_FLAGS="-L $CCH_TMUX_SOCKET"

    # Stub claude with a sleeper so spawned windows don't try to run real claude.
    export CCH_CLAUDE="$FIXTURES/claude-stub.sh"

    # Force session name so tests can find it predictably.
    export CCH_SESSION="cch-test-$$"

    # Disable color in tests for stable output assertions.
    export NO_COLOR=1

    unset CCH_HOME CCH_FLAGS
}

teardown_test_env() {
    tmux $TMUX_TEST_FLAGS kill-server 2>/dev/null || true
    rm -rf "$BATS_TEST_TMPDIR"
}

# Run cc-harness with the test environment's tmux socket prepended.
run_cch() {
    run env TMUX_FLAGS="$TMUX_TEST_FLAGS" "$CCH_BIN" "$@"
}

# Wait up to N seconds for a tmux window with the given name.
wait_for_window() {
    local name="$1" timeout="${2:-3}" elapsed=0
    while ! tmux $TMUX_TEST_FLAGS list-windows -t "$CCH_SESSION" -F '#W' 2>/dev/null \
        | grep -qx -- "$name"; do
        (( elapsed >= timeout * 10 )) && return 1
        sleep 0.1
        (( elapsed++ ))
    done
}
```

- [ ] **Step 3: Write `tests/fixtures/claude-stub.sh`**

```bash
#!/usr/bin/env bash
# Test stub for `claude` binary. Sleeps so the tmux pane stays alive.
case "${1:-}" in
    --version) echo "claude-stub 0.0.0-test"; exit 0 ;;
esac
exec sleep 9999
```

Make it executable: `chmod +x tests/fixtures/claude-stub.sh`

- [ ] **Step 4: Write fixture configs**

`tests/fixtures/projects.conf.basic`:
```
foo = /tmp/foo
bar = /tmp/bar
```

`tests/fixtures/projects.conf.tagged`:
```
alpha = /tmp/alpha | --model opus     #live #trading
beta  = /tmp/beta                       #math
gamma = /tmp/gamma | --model haiku    #live
```

`tests/fixtures/projects.conf.malformed`:
```
no-equals
   = /tmp/missing-label
foo = /tmp/foo
foo = /tmp/duplicate
```

- [ ] **Step 5: Smoke test that bats runs**

Create `tests/unit/smoke.bats`:
```bash
#!/usr/bin/env bats
load '../test_helper.bash'

@test "bats harness boots" {
    [ "$(echo hello)" = "hello" ]
}
```

Run: `tests/bats/bin/bats tests/unit/smoke.bats`
Expected: `1 test, 0 failures`

- [ ] **Step 6: Commit**

```bash
git add .gitmodules tests/
git commit -m "test: bats-core submodule, helpers, fixtures"
```

---

### Task 3: Regression test for today's menu-respawn bug (must FAIL on current code)

**Files:**
- Create: `tests/integration/menu_respawn.bats`

- [ ] **Step 1: Write failing test**

```bash
#!/usr/bin/env bats
load '../test_helper.bash'

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "attach recreates the menu window when it has been killed" {
    # Boot the session.
    run_cch attach &
    local cch_pid=$!
    wait_for_window menu 5
    [ "$status" = "0" ] || true

    # Kill the menu window (simulates today's failure mode).
    tmux $TMUX_TEST_FLAGS kill-window -t "$CCH_SESSION:menu"

    # Confirm it's gone.
    run tmux $TMUX_TEST_FLAGS list-windows -t "$CCH_SESSION" -F '#W'
    [[ ! "$output" =~ ^menu$ ]]

    # Re-invoke attach. Today: no-op. After fix: menu reappears.
    run_cch attach
    wait_for_window menu 5

    # Assert window 0 exists again with name "menu".
    run tmux $TMUX_TEST_FLAGS list-windows -t "$CCH_SESSION" -F '#I:#W'
    [[ "$output" =~ ^0:menu ]]

    kill "$cch_pid" 2>/dev/null || true
}
```

- [ ] **Step 2: Run it — confirm FAILURE**

Run: `tests/bats/bin/bats tests/integration/menu_respawn.bats`
Expected: FAIL — current `_cmd_attach` does not recreate window 0.

- [ ] **Step 3: Commit (red test)**

```bash
git add tests/integration/menu_respawn.bats
git commit -m "test: regression for menu-window-vanished bug (currently failing)"
```

---

### Task 4: Implement menu auto-respawn fix

**Files:**
- Modify: `bin/cc-harness` (`_cmd_attach`)

- [ ] **Step 1: Edit `_cmd_attach` to ensure window 0 exists**

Replace the function body (around lines 161–176 of the current script) with:

```bash
_cmd_attach() {
    [[ -f "$CCH_CONF" ]] || _seed_conf
    if ! tmux has-session -t "$CCH_SESSION" 2>/dev/null; then
        tmux new-session -d -s "$CCH_SESSION" -n menu \
            "exec '$CCH_SELF' menu"
        tmux set-option -t "$CCH_SESSION" status-style "bg=colour236,fg=colour250"
        tmux set-option -t "$CCH_SESSION" status-left  "#[bold] cc-harness #[default]│ "
        tmux set-option -t "$CCH_SESSION" status-right "#(date +%H:%M) "
        tmux set-option -t "$CCH_SESSION" mouse on
    else
        # Self-heal: if the menu window has been killed, recreate it at index 0.
        if ! tmux list-windows -t "$CCH_SESSION" -F '#W' 2>/dev/null | grep -qx menu; then
            tmux new-window -t "$CCH_SESSION:0" -n menu \
                "exec '$CCH_SELF' menu" 2>/dev/null \
                || tmux new-window -t "$CCH_SESSION:" -n menu \
                       "exec '$CCH_SELF' menu"
        fi
    fi
    if [[ -n "${TMUX:-}" ]]; then
        tmux switch-client -t "$CCH_SESSION"
    else
        tmux attach-session -t "$CCH_SESSION"
    fi
}
```

- [ ] **Step 2: Run the regression test — confirm PASS**

Run: `tests/bats/bin/bats tests/integration/menu_respawn.bats`
Expected: PASS.

- [ ] **Step 3: Commit (green)**

```bash
git add bin/cc-harness
git commit -m "fix: recreate menu window on attach when it has been killed"
```

---

## Phase B — Path resolution and XDG migration

### Task 5: Path resolution helpers (CCH_HOME → XDG → legacy)

**Files:**
- Modify: `bin/cc-harness` (add `_lib_paths`)
- Create: `tests/unit/path_resolution.bats`

- [ ] **Step 1: Write failing tests**

```bash
#!/usr/bin/env bats
load '../test_helper.bash'

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "CCH_HOME wins over XDG and legacy" {
    mkdir -p "$HOME/custom"
    echo "foo = /tmp" > "$HOME/custom/projects.conf"
    export CCH_HOME="$HOME/custom"
    run_cch _debug-paths
    [[ "$output" =~ "config=$HOME/custom/projects.conf" ]]
}

@test "XDG wins over legacy when XDG file exists" {
    mkdir -p "$XDG_CONFIG_HOME/cc-harness" "$HOME/cc-harness"
    echo "foo = /tmp" > "$XDG_CONFIG_HOME/cc-harness/projects.conf"
    echo "bar = /tmp" > "$HOME/cc-harness/projects.conf"
    run_cch _debug-paths
    [[ "$output" =~ "config=$XDG_CONFIG_HOME/cc-harness/projects.conf" ]]
}

@test "legacy is used when XDG file absent" {
    mkdir -p "$HOME/cc-harness"
    echo "foo = /tmp" > "$HOME/cc-harness/projects.conf"
    run_cch _debug-paths
    [[ "$output" =~ "config=$HOME/cc-harness/projects.conf" ]]
}

@test "fresh install resolves to XDG default with no file yet" {
    run_cch _debug-paths
    [[ "$output" =~ "config=$XDG_CONFIG_HOME/cc-harness/projects.conf" ]]
}
```

- [ ] **Step 2: Run — expected to fail (helper doesn't exist)**

Run: `tests/bats/bin/bats tests/unit/path_resolution.bats`
Expected: FAIL — `_debug-paths` is not a recognized command.

- [ ] **Step 3: Add `_lib_paths` and `_debug-paths` hidden command**

Insert near the top of `bin/cc-harness`, after the existing globals:

```bash
_lib_paths() {
    local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}"
    local xdg_state="${XDG_STATE_HOME:-$HOME/.local/state}"
    local legacy_dir="$HOME/cc-harness"

    # Priority chain: CCH_HOME → XDG → legacy
    if [[ -n "${CCH_HOME:-}" ]]; then
        CCH_CONF="$CCH_HOME/projects.conf"
        CCH_STATE_DIR="$CCH_HOME"
    elif [[ -f "$xdg_config/cc-harness/projects.conf" ]]; then
        CCH_CONF="$xdg_config/cc-harness/projects.conf"
        CCH_STATE_DIR="$xdg_state/cc-harness"
    elif [[ -f "$legacy_dir/projects.conf" ]]; then
        CCH_CONF="$legacy_dir/projects.conf"
        CCH_STATE_DIR="$legacy_dir"
    else
        CCH_CONF="$xdg_config/cc-harness/projects.conf"
        CCH_STATE_DIR="$xdg_state/cc-harness"
    fi
    CCH_LOCK="${XDG_RUNTIME_DIR:-/tmp}/cc-harness-$UID.lock"
    CCH_LOG="$CCH_STATE_DIR/cc-harness.log"
    CCH_MIGRATED_MARKER="$CCH_STATE_DIR/.migrated-from-legacy"
}
```

Replace the existing `CCH_CONF=` definition with a call to `_lib_paths` at the top of the dispatch:

```bash
_lib_paths
```

(Place this call just before the `case "${1:-attach}"` block, so subcommands see populated paths.)

Add a hidden `_debug-paths` command in the dispatch:

```bash
        _debug-paths) printf "config=%s\nstate=%s\nlock=%s\n" \
            "$CCH_CONF" "$CCH_STATE_DIR" "$CCH_LOCK" ;;
```

- [ ] **Step 4: Run tests — expected PASS**

Run: `tests/bats/bin/bats tests/unit/path_resolution.bats`
Expected: 4 passing.

- [ ] **Step 5: Commit**

```bash
git add bin/cc-harness tests/unit/path_resolution.bats
git commit -m "feat: XDG-aware path resolution with CCH_HOME and legacy fallbacks"
```

---

### Task 6: XDG migration — tests

**Files:**
- Create: `tests/integration/migration.bats`

- [ ] **Step 1: Write failing tests**

```bash
#!/usr/bin/env bats
load '../test_helper.bash'

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "migration: copies legacy projects.conf to XDG and writes marker" {
    mkdir -p "$HOME/cc-harness"
    echo "foo = /tmp/foo" > "$HOME/cc-harness/projects.conf"

    run_cch list
    [ "$status" -eq 0 ]

    [ -f "$XDG_CONFIG_HOME/cc-harness/projects.conf" ]
    [ -f "$XDG_STATE_HOME/cc-harness/.migrated-from-legacy" ]
    grep -q "foo = /tmp/foo" "$XDG_CONFIG_HOME/cc-harness/projects.conf"
}

@test "migration: prints one-time stderr notice" {
    mkdir -p "$HOME/cc-harness"
    echo "foo = /tmp/foo" > "$HOME/cc-harness/projects.conf"

    run --separate-stderr "$CCH_BIN" list
    [[ "$stderr" =~ "migrated config from" ]]
}

@test "migration: does NOT run when CCH_HOME is set" {
    mkdir -p "$HOME/cc-harness" "$HOME/custom"
    echo "foo = /tmp/foo" > "$HOME/cc-harness/projects.conf"
    echo "bar = /tmp/bar" > "$HOME/custom/projects.conf"
    export CCH_HOME="$HOME/custom"

    run_cch list
    [ ! -f "$XDG_CONFIG_HOME/cc-harness/projects.conf" ]
}

@test "migration: idempotent — second run skips silently" {
    mkdir -p "$HOME/cc-harness"
    echo "foo = /tmp/foo" > "$HOME/cc-harness/projects.conf"

    run_cch list  # first run migrates
    run_cch list  # second run: marker present, no notice
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "migrated config from" ]]
}

@test "migration: legacy directory is left in place" {
    mkdir -p "$HOME/cc-harness"
    echo "foo = /tmp/foo" > "$HOME/cc-harness/projects.conf"
    run_cch list
    [ -f "$HOME/cc-harness/projects.conf" ]
}
```

- [ ] **Step 2: Run — expected FAIL**

Run: `tests/bats/bin/bats tests/integration/migration.bats`
Expected: All five fail (`list` doesn't exist yet, migration doesn't run).

- [ ] **Step 3: Commit (red)**

```bash
git add tests/integration/migration.bats
git commit -m "test: XDG migration regression suite (currently failing)"
```

---

### Task 7: Implement XDG migration

**Files:**
- Modify: `bin/cc-harness`

- [ ] **Step 1: Add `_lib_migrate` after `_lib_paths`**

```bash
_lib_migrate() {
    local legacy_dir="$HOME/cc-harness"
    local xdg_config="${XDG_CONFIG_HOME:-$HOME/.config}/cc-harness"

    # Skip if CCH_HOME explicit, no legacy file, or marker already present.
    [[ -n "${CCH_HOME:-}" ]] && return 0
    [[ -f "$legacy_dir/projects.conf" ]] || return 0
    [[ -f "$CCH_MIGRATED_MARKER" ]] && return 0
    [[ -f "$xdg_config/projects.conf" ]] && return 0  # already at XDG

    mkdir -p "$xdg_config" "$CCH_STATE_DIR"
    cp -p "$legacy_dir/projects.conf" "$xdg_config/projects.conf"
    : > "$CCH_MIGRATED_MARKER"

    {
        echo "cc-harness: migrated config from ~/cc-harness/ to $xdg_config/"
        echo "cc-harness: legacy ~/cc-harness/ left in place; remove when ready"
    } >&2

    # Re-resolve so subsequent code uses the new path.
    CCH_CONF="$xdg_config/projects.conf"
}
```

Call `_lib_migrate` immediately after `_lib_paths` at the top of dispatch:

```bash
_lib_paths
_lib_migrate
```

- [ ] **Step 2: Add a stub `list` command (final impl in Task 18)**

```bash
        list)
            grep -vE '^\s*(#|$)' "$CCH_CONF" 2>/dev/null || true
            ;;
```

- [ ] **Step 3: Run migration tests — expected PASS**

Run: `tests/bats/bin/bats tests/integration/migration.bats`
Expected: 5 passing.

- [ ] **Step 4: Commit**

```bash
git add bin/cc-harness
git commit -m "feat: one-time XDG migration from ~/cc-harness/"
```

---

## Phase C — Config parser and validation

### Task 8: Extended schema parser (label / path / flags / tags)

**Files:**
- Modify: `bin/cc-harness` (add `_lib_parse`)
- Create: `tests/unit/parse_config.bats`

- [ ] **Step 1: Write failing tests**

```bash
#!/usr/bin/env bats
load '../test_helper.bash'

setup() { setup_test_env; }
teardown() { teardown_test_env; }

parse_line() {
    "$CCH_BIN" _parse-line "$1"
}

@test "parse: bare label = path" {
    run parse_line "foo = /tmp/foo"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "label=foo" ]]
    [[ "$output" =~ "path=/tmp/foo" ]]
    [[ "$output" =~ "flags=" ]]
    [[ "$output" =~ "tags=" ]]
}

@test "parse: with flags" {
    run parse_line "foo = /tmp/foo | --model opus"
    [[ "$output" =~ "flags=--model opus" ]]
}

@test "parse: with tags" {
    run parse_line "foo = /tmp/foo #live #trading"
    [[ "$output" =~ "tags=live trading" ]]
}

@test "parse: with flags and tags" {
    run parse_line "foo = /tmp/foo | --model opus  #live #trading"
    [[ "$output" =~ "flags=--model opus" ]]
    [[ "$output" =~ "tags=live trading" ]]
}

@test "parse: ~ in path expanded later (parser preserves literal)" {
    run parse_line "home = ~"
    [[ "$output" =~ "path=~" ]]
}

@test "parse: multiple equals signs — split on first only" {
    run parse_line "weird = /tmp/foo=bar"
    [[ "$output" =~ "path=/tmp/foo=bar" ]]
}
```

- [ ] **Step 2: Add `_lib_parse` and `_parse-line` debug command**

```bash
_lib_parse() {
    # $1 = raw line; emits label/path/flags/tags as KEY=value pairs on stdout.
    local line="$1" label rest path flags tags
    line="${line#"${line%%[![:space:]]*}"}"  # ltrim
    [[ -z "$line" || "$line" == \#* ]] && return 1

    label="${line%%=*}"
    label="${label%"${label##*[![:space:]]}"}"  # rtrim label
    rest="${line#*=}"
    rest="${rest#"${rest%%[![:space:]]*}"}"      # ltrim rest

    # Split off trailing tags (#tag tokens at end).
    tags=""
    while [[ "$rest" =~ [[:space:]]\#([a-zA-Z0-9_-]+)[[:space:]]*$ ]]; do
        tags="${BASH_REMATCH[1]} $tags"
        rest="${rest% \#${BASH_REMATCH[1]}*}"
        rest="${rest%"${rest##*[![:space:]]}"}"
    done
    tags="${tags% }"

    # Split off flags (after | if present).
    if [[ "$rest" == *"|"* ]]; then
        flags="${rest#*|}"
        flags="${flags#"${flags%%[![:space:]]*}"}"
        flags="${flags%"${flags##*[![:space:]]}"}"
        path="${rest%%|*}"
        path="${path%"${path##*[![:space:]]}"}"
    else
        path="${rest%"${rest##*[![:space:]]}"}"
        flags=""
    fi

    printf "label=%s\npath=%s\nflags=%s\ntags=%s\n" "$label" "$path" "$flags" "$tags"
}
```

Add hidden dispatch entry:

```bash
        _parse-line) shift; _lib_parse "$1" ;;
```

- [ ] **Step 3: Run — expected PASS**

Run: `tests/bats/bin/bats tests/unit/parse_config.bats`
Expected: 6 passing.

- [ ] **Step 4: Commit**

```bash
git add bin/cc-harness tests/unit/parse_config.bats
git commit -m "feat: schema-extended config parser (label/path/flags/tags)"
```

---

### Task 9: Label, tag, and path validation

**Files:**
- Modify: `bin/cc-harness` (add `_lib_validate`)
- Create: `tests/unit/label_validation.bats`

- [ ] **Step 1: Write failing tests**

```bash
#!/usr/bin/env bats
load '../test_helper.bash'

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "label: alnum + dash + underscore allowed" {
    run "$CCH_BIN" _validate-label "foo-bar_1"
    [ "$status" -eq 0 ]
}

@test "label: empty rejected" {
    run "$CCH_BIN" _validate-label ""
    [ "$status" -eq 3 ]
}

@test "label: spaces rejected" {
    run "$CCH_BIN" _validate-label "foo bar"
    [ "$status" -eq 3 ]
}

@test "label: too long rejected (>32)" {
    run "$CCH_BIN" _validate-label "$(printf 'a%.0s' {1..33})"
    [ "$status" -eq 3 ]
}

@test "tag: alnum + dash + underscore allowed" {
    run "$CCH_BIN" _validate-tag "live-1"
    [ "$status" -eq 0 ]
}

@test "tag: too long rejected (>24)" {
    run "$CCH_BIN" _validate-tag "$(printf 'a%.0s' {1..25})"
    [ "$status" -eq 3 ]
}
```

- [ ] **Step 2: Add `_lib_validate` and dispatch entries**

```bash
_lib_validate_label() {
    local label="$1"
    [[ -z "$label" ]] && { echo "cc-harness: label cannot be empty" >&2; return 3; }
    (( ${#label} > 32 )) && { echo "cc-harness: label too long (max 32)" >&2; return 3; }
    [[ "$label" =~ ^[a-zA-Z0-9_-]+$ ]] || {
        echo "cc-harness: label must match [a-zA-Z0-9_-]+" >&2; return 3; }
    return 0
}

_lib_validate_tag() {
    local tag="$1"
    [[ -z "$tag" ]] && { echo "cc-harness: tag cannot be empty" >&2; return 3; }
    (( ${#tag} > 24 )) && { echo "cc-harness: tag too long (max 24)" >&2; return 3; }
    [[ "$tag" =~ ^[a-zA-Z0-9_-]+$ ]] || {
        echo "cc-harness: tag must match [a-zA-Z0-9_-]+" >&2; return 3; }
    return 0
}

_lib_resolve_path() {
    local p="$1"; p="${p/#\~/$HOME}"; printf "%s" "$p"
}

_lib_validate_path() {
    local p; p="$(_lib_resolve_path "$1")"
    [[ -d "$p" ]] || { echo "cc-harness: not a directory: $p" >&2; return 3; }
    return 0
}
```

Dispatch:

```bash
        _validate-label) shift; _lib_validate_label "$1" ;;
        _validate-tag)   shift; _lib_validate_tag "$1" ;;
        _validate-path)  shift; _lib_validate_path "$1" ;;
```

- [ ] **Step 3: Run — expected PASS**

Run: `tests/bats/bin/bats tests/unit/label_validation.bats`
Expected: 6 passing.

- [ ] **Step 4: Commit**

```bash
git add bin/cc-harness tests/unit/label_validation.bats
git commit -m "feat: label/tag/path validators"
```

---

## Phase D — Robustness primitives

### Task 10: Error reporting and exit codes

**Files:**
- Modify: `bin/cc-harness` (add `_lib_error`, exit-code constants)

- [ ] **Step 1: Add helpers near top of script**

```bash
readonly EXIT_OK=0
readonly EXIT_GENERIC=1
readonly EXIT_USAGE=2
readonly EXIT_CONFIG=3
readonly EXIT_TMUX=4
readonly EXIT_DEPS=5

_die() {
    # _die <exit-code> <subcmd> <message...>
    local code="$1" subcmd="$2"; shift 2
    printf "cc-harness: %s: %s\n" "$subcmd" "$*" >&2
    exit "$code"
}

_warn() {
    local subcmd="$1"; shift
    printf "cc-harness: %s: %s\n" "$subcmd" "$*" >&2
}
```

- [ ] **Step 2: Replace existing ad-hoc `printf … >&2` calls in `_spawn` with `_die`**

In `_spawn`, replace:
```bash
        printf "cc-harness: no such dir: %s\n" "$path" >&2
        sleep 1.5
        return 1
```
with:
```bash
        _die "$EXIT_CONFIG" spawn "no such dir: $path"
```

- [ ] **Step 3: Manual smoke**

Run: `bin/cc-harness new`  with a malformed projects.conf entry pointing to a non-existent dir.
Expected: stderr includes `cc-harness: spawn: no such dir: …`, exit code 3.

- [ ] **Step 4: Commit**

```bash
git add bin/cc-harness
git commit -m "feat: structured error reporting and exit-code constants"
```

---

### Task 11: Logging (`-v`/`--verbose`) with rotation

**Files:**
- Modify: `bin/cc-harness` (add `_lib_log`, global flag parsing)

- [ ] **Step 1: Add `_lib_log`**

```bash
_lib_log() {
    [[ "${CCH_VERBOSE:-0}" -eq 1 ]] || return 0
    mkdir -p "$CCH_STATE_DIR"
    # Rotate if log > 1MiB; keep 3.
    if [[ -f "$CCH_LOG" ]] && (( $(stat -c%s "$CCH_LOG" 2>/dev/null || stat -f%z "$CCH_LOG") > 1048576 )); then
        for i in 2 1; do
            [[ -f "$CCH_LOG.$i" ]] && mv "$CCH_LOG.$i" "$CCH_LOG.$((i+1))"
        done
        mv "$CCH_LOG" "$CCH_LOG.1"
    fi
    printf "[%s] %s\n" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$CCH_LOG"
}
```

- [ ] **Step 2: Parse `-v`/`--verbose` and `-q`/`--quiet` as leading global flags**

Add before the case dispatch:

```bash
_lib_parse_global_flags() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose) CCH_VERBOSE=1; shift ;;
            -q|--quiet)   CCH_QUIET=1; shift ;;
            --no-color)   NO_COLOR=1; shift ;;
            *) break ;;
        esac
    done
    CCH_REMAINING_ARGS=("$@")
}

_lib_parse_global_flags "$@"
set -- "${CCH_REMAINING_ARGS[@]}"
```

- [ ] **Step 3: Smoke**

Run: `bin/cc-harness -v list >/dev/null && cat $XDG_STATE_HOME/cc-harness/cc-harness.log`
Expected: log file exists with at least one timestamped entry.

- [ ] **Step 4: Commit**

```bash
git add bin/cc-harness
git commit -m "feat: -v/-q/--no-color global flags + log file with rotation"
```

---

### Task 12: Lockfile around config-mutating ops

**Files:**
- Modify: `bin/cc-harness` (add `_lib_lock`)

- [ ] **Step 1: Add helper**

```bash
_lib_with_lock() {
    # _lib_with_lock <subcmd> <function-to-run> [args...]
    local subcmd="$1" fn="$2"; shift 2
    mkdir -p "$(dirname "$CCH_LOCK")"
    exec 9>"$CCH_LOCK" || _die "$EXIT_GENERIC" "$subcmd" "could not open lockfile $CCH_LOCK"
    if ! flock -n 9; then
        _die "$EXIT_GENERIC" "$subcmd" "another cc-harness is mutating config (lock held)"
    fi
    "$fn" "$@"
    local rc=$?
    exec 9>&-
    return "$rc"
}
```

- [ ] **Step 2: Smoke**

Run two `cc-harness add` calls in parallel (after Task 19):
```
( bin/cc-harness add t1 /tmp & bin/cc-harness add t2 /tmp & wait )
```
Expected: both succeed sequentially, no corruption.

(For now, manual verification only; Task 19 wires this in.)

- [ ] **Step 3: Commit**

```bash
git add bin/cc-harness
git commit -m "feat: flock-based mutex helper for config-mutating ops"
```

---

### Task 13: Preflight checks (claude binary, tmux version, dir)

**Files:**
- Modify: `bin/cc-harness` (add `_lib_preflight_*`)
- Create: `tests/unit/preflight.bats`

- [ ] **Step 1: Write failing tests**

```bash
#!/usr/bin/env bats
load '../test_helper.bash'

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "preflight: missing claude binary -> exit 5" {
    export CCH_CLAUDE="$BATS_TEST_TMPDIR/does-not-exist"
    run_cch _preflight-claude
    [ "$status" -eq 5 ]
    [[ "$output" =~ "claude binary not found" ]]
}

@test "preflight: present claude binary -> exit 0" {
    run_cch _preflight-claude
    [ "$status" -eq 0 ]
}

@test "preflight: tmux present and recent -> exit 0" {
    run_cch _preflight-tmux
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Add helpers**

```bash
_lib_preflight_claude() {
    if ! command -v "$CCH_CLAUDE" >/dev/null 2>&1; then
        _die "$EXIT_DEPS" preflight \
            "claude binary not found on PATH (or via \$CCH_CLAUDE=$CCH_CLAUDE)"
    fi
}

_lib_preflight_tmux() {
    command -v tmux >/dev/null 2>&1 \
        || _die "$EXIT_DEPS" preflight "tmux not installed"
    local v
    v="$(tmux -V | awk '{print $2}' | tr -d '[:alpha:]')"
    awk -v v="$v" 'BEGIN{ exit !(v+0 >= 3.0) }' \
        || _die "$EXIT_DEPS" preflight "requires tmux >= 3.0 (found $v)"
}
```

Dispatch:

```bash
        _preflight-claude) _lib_preflight_claude ;;
        _preflight-tmux)   _lib_preflight_tmux ;;
```

- [ ] **Step 3: Run — expected PASS**

Run: `tests/bats/bin/bats tests/unit/preflight.bats`
Expected: 3 passing.

- [ ] **Step 4: Commit**

```bash
git add bin/cc-harness tests/unit/preflight.bats
git commit -m "feat: preflight checks for claude binary and tmux version"
```

---

## Phase E — Existing subcommands hardened

### Task 14: Refactor `_spawn` and `_cmd_attach` to use new helpers

**Files:**
- Modify: `bin/cc-harness`

- [ ] **Step 1: Wire preflight + path validation into `_spawn`**

Replace `_spawn` body with:

```bash
_spawn() {
    local label="$1" path="$2" extra_flags="${3:-}"
    _lib_validate_label "$label" || exit "$EXIT_CONFIG"
    path="$(_lib_resolve_path "$path")"
    [[ -d "$path" ]] || _die "$EXIT_CONFIG" spawn "no such dir: $path"
    _lib_preflight_claude
    _lib_preflight_tmux
    if tmux list-windows -t "$CCH_SESSION" -F '#W' 2>/dev/null | grep -qx -- "$label"; then
        tmux select-window -t "$CCH_SESSION:$label"
    else
        tmux new-window -t "$CCH_SESSION:" -n "$label" -c "$path" \
            "$CCH_CLAUDE $CCH_FLAGS $extra_flags"
        tmux select-window -t "$CCH_SESSION:$label"
    fi
    _lib_log "spawn label=$label path=$path"
}
```

- [ ] **Step 2: Run regression suite**

Run: `tests/bats/bin/bats tests/`
Expected: all current tests still pass.

- [ ] **Step 3: Commit**

```bash
git add bin/cc-harness
git commit -m "refactor: use validation + preflight helpers in _spawn"
```

---

### Task 15: Stale-window detection on attach

**Files:**
- Modify: `bin/cc-harness`
- Create: `tests/integration/stale_window.bats`

- [ ] **Step 1: Write test**

```bash
#!/usr/bin/env bats
load '../test_helper.bash'

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "stale window is renamed to [dead] <label> on attach" {
    # Boot with a stub that exits immediately so the window is "dead".
    cat > "$BATS_TEST_TMPDIR/quick-stub.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/quick-stub.sh"
    export CCH_CLAUDE="$BATS_TEST_TMPDIR/quick-stub.sh"

    mkdir -p "$XDG_CONFIG_HOME/cc-harness"
    echo "deadproj = $HOME" > "$XDG_CONFIG_HOME/cc-harness/projects.conf"

    run_cch attach &
    wait_for_window menu 5
    "$CCH_BIN" new deadproj || true
    sleep 0.5

    # Re-attach; stale detection should rename window.
    "$CCH_BIN" attach
    run tmux $TMUX_TEST_FLAGS list-windows -t "$CCH_SESSION" -F '#W'
    [[ "$output" =~ \[dead\]\ deadproj ]]
}
```

- [ ] **Step 2: Add detection in `_cmd_attach`**

After the menu auto-respawn block, add:

```bash
    # Stale-window detection: rename windows whose pane PID is dead.
    while IFS=$'\t' read -r idx wname pid; do
        [[ "$wname" == menu || "$wname" == \[dead\]* ]] && continue
        if ! kill -0 "$pid" 2>/dev/null; then
            tmux rename-window -t "$CCH_SESSION:$idx" "[dead] $wname"
        fi
    done < <(tmux list-windows -t "$CCH_SESSION" -F '#I	#W	#{pane_pid}' 2>/dev/null)
```

- [ ] **Step 3: Run test — expected PASS**

Run: `tests/bats/bin/bats tests/integration/stale_window.bats`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add bin/cc-harness tests/integration/stale_window.bats
git commit -m "feat: rename windows of dead claudes to [dead] <label> on attach"
```

---

### Task 16: Multi-instance — `cc-harness new <label> --fresh|--switch`

**Files:**
- Modify: `bin/cc-harness` (`_cmd_new`)
- Create: `tests/integration/spawn_fresh.bats`

- [ ] **Step 1: Write tests**

```bash
#!/usr/bin/env bats
load '../test_helper.bash'

setup() {
    setup_test_env
    mkdir -p "$XDG_CONFIG_HOME/cc-harness"
    echo "alpha = $HOME" > "$XDG_CONFIG_HOME/cc-harness/projects.conf"
    "$CCH_BIN" attach &
    sleep 0.3
}
teardown() { teardown_test_env; }

@test "new <label> default: switches to existing window" {
    "$CCH_BIN" new alpha
    "$CCH_BIN" new alpha
    run tmux $TMUX_TEST_FLAGS list-windows -t "$CCH_SESSION" -F '#W'
    # Only one alpha window.
    [ "$(echo "$output" | grep -c '^alpha$')" -eq 1 ]
}

@test "new <label> --fresh: creates alpha-2" {
    "$CCH_BIN" new alpha
    "$CCH_BIN" new alpha --fresh
    run tmux $TMUX_TEST_FLAGS list-windows -t "$CCH_SESSION" -F '#W'
    [[ "$output" =~ ^alpha-2$ ]] || [[ "$output" =~ alpha-2 ]]
}

@test "new <label> --switch with no existing window: errors" {
    run "$CCH_BIN" new alpha --switch
    [ "$status" -eq 4 ]
}
```

- [ ] **Step 2: Implement `_cmd_new` with mode-aware spawning**

Replace `_cmd_new` with:

```bash
_cmd_new() {
    local mode=ask label=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fresh)  mode=fresh; shift ;;
            --switch) mode=switch; shift ;;
            -*)       _die "$EXIT_USAGE" new "unknown flag: $1" ;;
            *)        label="$1"; shift ;;
        esac
    done

    if [[ -z "$label" ]]; then
        local pick path flags tags
        pick="$(_projects | _pick 'project>')" || return 0
        [[ -z "${pick:-}" ]] && return 0
        label="$(printf "%s" "${pick%%=*}" | tr -d '[:space:]')"
    fi

    # Look up project line.
    local line; line="$(_lookup_project "$label")" \
        || _die "$EXIT_CONFIG" new "no such project: $label"
    local path flags
    eval "$(_lib_parse "$line")"

    local exists=0
    tmux list-windows -t "$CCH_SESSION" -F '#W' 2>/dev/null \
        | grep -qx -- "$label" && exists=1

    case "$mode" in
        switch)
            (( exists )) || _die "$EXIT_TMUX" new "no window for $label"
            tmux select-window -t "$CCH_SESSION:$label"
            ;;
        fresh)
            local n=2
            while tmux list-windows -t "$CCH_SESSION" -F '#W' 2>/dev/null \
                | grep -qx -- "$label-$n"; do (( n++ )); done
            _spawn "$label-$n" "$path" "$flags"
            ;;
        ask)
            if (( exists )); then
                read -r -p "[s]witch / [f]resh / [c]ancel? " ans
                case "${ans:-s}" in
                    s|S|"") tmux select-window -t "$CCH_SESSION:$label" ;;
                    f|F)
                        local n=2
                        while tmux list-windows -t "$CCH_SESSION" -F '#W' 2>/dev/null \
                            | grep -qx -- "$label-$n"; do (( n++ )); done
                        _spawn "$label-$n" "$path" "$flags"
                        ;;
                    *) return 0 ;;
                esac
            else
                _spawn "$label" "$path" "$flags"
            fi
            ;;
    esac
}

_lookup_project() {
    local want="$1" line label
    while IFS= read -r line; do
        eval "$(_lib_parse "$line" 2>/dev/null)" || continue
        [[ "$label" == "$want" ]] && { printf "%s\n" "$line"; return 0; }
    done < <(grep -vE '^\s*(#|$)' "$CCH_CONF")
    return 1
}
```

- [ ] **Step 3: Run tests — expected PASS**

Run: `tests/bats/bin/bats tests/integration/spawn_fresh.bats`
Expected: 3 passing.

- [ ] **Step 4: Commit**

```bash
git add bin/cc-harness tests/integration/spawn_fresh.bats
git commit -m "feat: cc-harness new --fresh / --switch (multi-instance per project)"
```

---

### Task 17: `_cmd_kill` — `--all`, `--tag`, `--dry-run`

**Files:**
- Modify: `bin/cc-harness` (`_cmd_kill`)

- [ ] **Step 1: Replace `_cmd_kill`**

```bash
_cmd_kill() {
    local all=0 tag="" dry=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --all)      all=1; shift ;;
            --tag)      tag="$2"; shift 2 ;;
            --dry-run)  dry=1; shift ;;
            *) _die "$EXIT_USAGE" kill "unknown flag: $1" ;;
        esac
    done
    local windows pick
    windows="$(tmux list-windows -t "$CCH_SESSION" -F '#W' 2>/dev/null \
        | grep -vx menu || true)"
    if [[ -z "$windows" ]]; then
        printf "(no sessions to kill)\n" >&2; return 0
    fi
    if [[ -n "$tag" ]]; then
        windows="$(_filter_windows_by_tag "$windows" "$tag")"
        [[ -z "$windows" ]] && { printf "(no sessions match tag #%s)\n" "$tag" >&2; return 0; }
    fi
    if (( all )); then
        while IFS= read -r w; do
            (( dry )) && { printf "would kill: %s\n" "$w"; continue; }
            tmux kill-window -t "$CCH_SESSION:$w"
        done <<< "$windows"
        return 0
    fi
    pick="$(printf "%s\n" "$windows" | _pick 'kill>')" || return 0
    [[ -z "${pick:-}" ]] && return 0
    if (( dry )); then printf "would kill: %s\n" "$pick"; return 0; fi
    printf "kill window '%s'? [y/N] " "$pick" >&2
    local ans; read -r ans </dev/tty
    [[ "$ans" == "y" || "$ans" == "Y" ]] || return 0
    tmux kill-window -t "$CCH_SESSION:$pick"
}

_filter_windows_by_tag() {
    local windows="$1" want_tag="$2" out="" line label tags
    while IFS= read -r line; do
        eval "$(_lib_parse "$line" 2>/dev/null)" || continue
        for w in $windows; do
            local base="${w%-[0-9]*}"
            [[ "$base" == "$label" ]] || continue
            for t in $tags; do
                [[ "${t,,}" == "${want_tag,,}" ]] && out+="$w"$'\n'
            done
        done
    done < <(grep -vE '^\s*(#|$)' "$CCH_CONF")
    printf "%s" "${out%$'\n'}"
}
```

- [ ] **Step 2: Manual verification**

```
bin/cc-harness new alpha
bin/cc-harness new alpha --fresh
bin/cc-harness kill --dry-run --all
```
Expected output:
```
would kill: alpha
would kill: alpha-2
```

- [ ] **Step 3: Commit**

```bash
git add bin/cc-harness
git commit -m "feat: cc-harness kill --all / --tag / --dry-run"
```

---

## Phase F — Config-mutating subcommands

### Task 18: `cc-harness list` (with `--tag`, `--tags`)

**Files:**
- Modify: `bin/cc-harness`

- [ ] **Step 1: Replace stub `list` with full implementation**

```bash
_cmd_list() {
    local tag="" show_tags=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tag)    tag="$2"; shift 2 ;;
            --tags)   show_tags=1; shift ;;
            *) _die "$EXIT_USAGE" list "unknown flag: $1" ;;
        esac
    done

    if (( show_tags )); then
        local all_tags=""
        while IFS= read -r line; do
            eval "$(_lib_parse "$line" 2>/dev/null)" || continue
            for t in $tags; do all_tags+="$t"$'\n'; done
        done < <(grep -vE '^\s*(#|$)' "$CCH_CONF")
        printf "%s\n" "$all_tags" | sort | uniq -c \
            | awk '{printf "#%s (%d)\n", $2, $1}' | sort
        return 0
    fi

    printf "%-16s %-40s %-8s %s\n" LABEL PATH EXISTS TAGS
    while IFS= read -r line; do
        eval "$(_lib_parse "$line" 2>/dev/null)" || continue
        local p; p="$(_lib_resolve_path "$path")"
        local ex="✗"; [[ -d "$p" ]] && ex="✓"

        if [[ -n "$tag" ]]; then
            local match=0
            for t in $tags; do [[ "${t,,}" == "${tag,,}" ]] && match=1; done
            (( match )) || continue
        fi

        local ttext=""
        for t in $tags; do ttext+="#$t "; done
        printf "%-16s %-40s %-8s %s\n" "$label" "$p" "$ex" "${ttext% }"
    done < <(grep -vE '^\s*(#|$)' "$CCH_CONF")
}
```

Replace dispatch entry:

```bash
        list) shift; _cmd_list "$@" ;;
```

- [ ] **Step 2: Manual verify**

Run: `bin/cc-harness list`
Expected: tabular output of projects.conf with EXISTS column.

- [ ] **Step 3: Commit**

```bash
git add bin/cc-harness
git commit -m "feat: cc-harness list with --tag and --tags discovery"
```

---

### Task 19: `cc-harness add`

**Files:**
- Modify: `bin/cc-harness`
- Create: `tests/integration/add_remove.bats`

- [ ] **Step 1: Write failing test**

```bash
#!/usr/bin/env bats
load '../test_helper.bash'

setup() {
    setup_test_env
    mkdir -p "$XDG_CONFIG_HOME/cc-harness"
    echo "" > "$XDG_CONFIG_HOME/cc-harness/projects.conf"
}
teardown() { teardown_test_env; }

@test "add: appends a row" {
    run_cch add proj1 "$HOME"
    [ "$status" -eq 0 ]
    grep -q "^proj1 = $HOME" "$XDG_CONFIG_HOME/cc-harness/projects.conf"
}

@test "add: rejects duplicate label" {
    run_cch add proj1 "$HOME"
    run_cch add proj1 "$HOME"
    [ "$status" -eq 3 ]
}

@test "add: rejects non-existent path" {
    run_cch add proj1 /does/not/exist
    [ "$status" -eq 3 ]
}

@test "add: with flags and tags" {
    run_cch add proj1 "$HOME" --flags "--model opus" --tag live --tag math
    [ "$status" -eq 0 ]
    grep -q "proj1 = $HOME | --model opus.*#live.*#math" \
        "$XDG_CONFIG_HOME/cc-harness/projects.conf"
}

@test "add --dry-run: no write" {
    run_cch add proj1 "$HOME" --dry-run
    [ "$status" -eq 0 ]
    ! grep -q "^proj1" "$XDG_CONFIG_HOME/cc-harness/projects.conf"
}
```

- [ ] **Step 2: Implement `_cmd_add`**

```bash
_cmd_add() {
    local label="" path="" flags="" tags=() dry=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --flags)    flags="$2"; shift 2 ;;
            --tag)      tags+=("$2"); shift 2 ;;
            --dry-run)  dry=1; shift ;;
            -*)         _die "$EXIT_USAGE" add "unknown flag: $1" ;;
            *)
                if [[ -z "$label" ]]; then label="$1"
                elif [[ -z "$path" ]]; then path="$1"
                else _die "$EXIT_USAGE" add "too many args: $1"
                fi
                shift
                ;;
        esac
    done
    [[ -n "$label" && -n "$path" ]] \
        || _die "$EXIT_USAGE" add "usage: add <label> <path> [--flags '...'] [--tag t]"
    _lib_validate_label "$label" || exit "$EXIT_CONFIG"
    _lib_validate_path "$path"   || exit "$EXIT_CONFIG"
    for t in "${tags[@]}"; do
        _lib_validate_tag "$t" || exit "$EXIT_CONFIG"
    done

    _lookup_project "$label" >/dev/null 2>&1 \
        && _die "$EXIT_CONFIG" add "label already exists: $label"

    local line="$label = $path"
    [[ -n "$flags" ]] && line+=" | $flags"
    for t in "${tags[@]}"; do line+=" #$t"; done

    if (( dry )); then printf "would append: %s\n" "$line"; return 0; fi

    _lib_with_lock add _cmd_add_write "$line"
}
_cmd_add_write() {
    [[ -f "$CCH_CONF" ]] || { mkdir -p "$(dirname "$CCH_CONF")"; touch "$CCH_CONF"; }
    printf "%s\n" "$1" >> "$CCH_CONF"
}
```

Dispatch:
```bash
        add) shift; _cmd_add "$@" ;;
```

- [ ] **Step 3: Run tests — expected PASS**

Run: `tests/bats/bin/bats tests/integration/add_remove.bats`
Expected: 5 passing (the `remove` ones in the next task).

- [ ] **Step 4: Commit**

```bash
git add bin/cc-harness tests/integration/add_remove.bats
git commit -m "feat: cc-harness add (with --flags, --tag, --dry-run)"
```

---

### Task 20: `cc-harness remove`

**Files:**
- Modify: `bin/cc-harness`
- Modify: `tests/integration/add_remove.bats`

- [ ] **Step 1: Append tests**

```bash
@test "remove: drops a row" {
    "$CCH_BIN" add proj1 "$HOME"
    run_cch remove proj1
    [ "$status" -eq 0 ]
    ! grep -q "^proj1" "$XDG_CONFIG_HOME/cc-harness/projects.conf"
}

@test "remove: errors on missing label" {
    run_cch remove ghost
    [ "$status" -eq 3 ]
}

@test "remove --dry-run" {
    "$CCH_BIN" add proj1 "$HOME"
    run_cch remove proj1 --dry-run
    [ "$status" -eq 0 ]
    grep -q "^proj1" "$XDG_CONFIG_HOME/cc-harness/projects.conf"
}
```

- [ ] **Step 2: Implement `_cmd_remove`**

```bash
_cmd_remove() {
    local label="" dry=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry=1; shift ;;
            -*) _die "$EXIT_USAGE" remove "unknown flag: $1" ;;
            *) label="$1"; shift ;;
        esac
    done
    [[ -n "$label" ]] || _die "$EXIT_USAGE" remove "usage: remove <label>"
    _lookup_project "$label" >/dev/null 2>&1 \
        || _die "$EXIT_CONFIG" remove "no such label: $label"
    if (( dry )); then printf "would remove: %s\n" "$label"; return 0; fi
    _lib_with_lock remove _cmd_remove_write "$label"
}
_cmd_remove_write() {
    local want="$1" tmp; tmp="$(mktemp)"
    awk -v w="$want" '
        /^\s*(#|$)/ { print; next }
        {
            split($0, a, "=")
            gsub(/^[ \t]+|[ \t]+$/, "", a[1])
            if (a[1] == w) next
            print
        }
    ' "$CCH_CONF" > "$tmp"
    mv "$tmp" "$CCH_CONF"
}
```

Dispatch:
```bash
        remove) shift; _cmd_remove "$@" ;;
```

- [ ] **Step 3: Run tests — expected PASS**

Run: `tests/bats/bin/bats tests/integration/add_remove.bats`
Expected: 8 passing.

- [ ] **Step 4: Commit**

```bash
git add bin/cc-harness tests/integration/add_remove.bats
git commit -m "feat: cc-harness remove (with --dry-run)"
```

---

### Task 21: `cc-harness rename`

**Files:**
- Modify: `bin/cc-harness`

- [ ] **Step 1: Implement**

```bash
_cmd_rename() {
    local old="" new="" dry=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry=1; shift ;;
            -*) _die "$EXIT_USAGE" rename "unknown flag: $1" ;;
            *)
                if [[ -z "$old" ]]; then old="$1"
                elif [[ -z "$new" ]]; then new="$1"
                else _die "$EXIT_USAGE" rename "too many args: $1"
                fi
                shift
                ;;
        esac
    done
    [[ -n "$old" && -n "$new" ]] \
        || _die "$EXIT_USAGE" rename "usage: rename <old> <new>"
    _lib_validate_label "$new" || exit "$EXIT_CONFIG"
    _lookup_project "$old" >/dev/null 2>&1 \
        || _die "$EXIT_CONFIG" rename "no such label: $old"
    _lookup_project "$new" >/dev/null 2>&1 \
        && _die "$EXIT_CONFIG" rename "target label already exists: $new"
    if (( dry )); then printf "would rename: %s -> %s\n" "$old" "$new"; return 0; fi

    _lib_with_lock rename _cmd_rename_write "$old" "$new"
    # Rename live tmux window if present.
    if tmux list-windows -t "$CCH_SESSION" -F '#W' 2>/dev/null | grep -qx -- "$old"; then
        tmux rename-window -t "$CCH_SESSION:$old" "$new"
    fi
}
_cmd_rename_write() {
    local old="$1" new="$2" tmp; tmp="$(mktemp)"
    awk -v o="$old" -v n="$new" '
        /^\s*(#|$)/ { print; next }
        {
            split($0, a, "=")
            label=a[1]; gsub(/^[ \t]+|[ \t]+$/, "", label)
            if (label == o) {
                rest=substr($0, index($0, "=")+1)
                printf "%s =%s\n", n, rest
            } else print
        }
    ' "$CCH_CONF" > "$tmp"
    mv "$tmp" "$CCH_CONF"
}
```

Dispatch:
```bash
        rename) shift; _cmd_rename "$@" ;;
```

- [ ] **Step 2: Smoke**

```
bin/cc-harness add foo $HOME
bin/cc-harness rename foo bar
grep '^bar = ' ~/.config/cc-harness/projects.conf
```
Expected: line shows `bar = ...`.

- [ ] **Step 3: Commit**

```bash
git add bin/cc-harness
git commit -m "feat: cc-harness rename (config + live tmux window)"
```

---

### Task 22: `cc-harness tag` and `untag`

**Files:**
- Modify: `bin/cc-harness`

- [ ] **Step 1: Implement**

```bash
_cmd_tag() {
    local label=""; local -a ops=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            +*|-*)
                ops+=("$1"); shift ;;
            *)
                if [[ -z "$label" ]]; then label="$1"
                else _die "$EXIT_USAGE" tag "too many args: $1"
                fi; shift ;;
        esac
    done
    [[ -n "$label" && ${#ops[@]} -gt 0 ]] \
        || _die "$EXIT_USAGE" tag "usage: tag <label> +foo -bar ..."
    _lookup_project "$label" >/dev/null 2>&1 \
        || _die "$EXIT_CONFIG" tag "no such label: $label"
    _lib_with_lock tag _cmd_tag_write "$label" "${ops[@]}"
}
_cmd_tag_write() {
    local target="$1"; shift
    local -a ops=("$@")
    local tmp; tmp="$(mktemp)"
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*# || -z "$line" ]]; then
            printf "%s\n" "$line" >> "$tmp"; continue
        fi
        # Parse with cc_ prefix so we don't clobber loop locals.
        local cc_label="" cc_path="" cc_flags="" cc_tags=""
        eval "$(CCH_PARSE_PREFIX=cc_ _lib_parse "$line")" || {
            printf "%s\n" "$line" >> "$tmp"; continue
        }
        if [[ "$cc_label" == "$target" ]]; then
            for op in "${ops[@]}"; do
                local sign="${op:0:1}" tag="${op:1}"
                _lib_validate_tag "$tag" || exit "$EXIT_CONFIG"
                case "$sign" in
                    +) [[ " $cc_tags " == *" $tag "* ]] || cc_tags="$cc_tags $tag" ;;
                    -) cc_tags=" $cc_tags "; cc_tags="${cc_tags// $tag / }" ;;
                esac
                cc_tags="${cc_tags## }"; cc_tags="${cc_tags%% }"
            done
            local out="$cc_label = $cc_path"
            [[ -n "$cc_flags" ]] && out+=" | $cc_flags"
            for t in $cc_tags; do out+=" #$t"; done
            printf "%s\n" "$out" >> "$tmp"
        else
            printf "%s\n" "$line" >> "$tmp"
        fi
    done < "$CCH_CONF"
    mv "$tmp" "$CCH_CONF"
}

_cmd_untag() {
    local label="${1:-}"
    [[ -n "$label" ]] || _die "$EXIT_USAGE" untag "usage: untag <label>"
    _lookup_project "$label" >/dev/null 2>&1 \
        || _die "$EXIT_CONFIG" untag "no such label: $label"
    _lib_with_lock untag _cmd_untag_write "$label"
}
_cmd_untag_write() {
    local label="$1" tmp; tmp="$(mktemp)"
    awk -v w="$label" '
        /^\s*(#|$)/ { print; next }
        {
            line=$0
            split(line, a, "=")
            l=a[1]; gsub(/^[ \t]+|[ \t]+$/, "", l)
            if (l == w) sub(/[[:space:]]+#.*$/, "", line)
            print line
        }
    ' "$CCH_CONF" > "$tmp"
    mv "$tmp" "$CCH_CONF"
}
```

Note: `_lib_parse` emits `label=...`, `path=...` etc. The function above uses `cc_*` prefix to avoid clobbering loop locals. Adjust `_lib_parse` to optionally prefix outputs:

Replace `_lib_parse` printf with:
```bash
    local prefix="${CCH_PARSE_PREFIX:-}"
    printf "%slabel=%s\n%spath=%s\n%sflags=%s\n%stags=%s\n" \
        "$prefix" "$label" "$prefix" "$path" "$prefix" "$flags" "$prefix" "$tags"
```

In `_cmd_tag_write`, set `CCH_PARSE_PREFIX=cc_` before eval'ing `_lib_parse`.

Dispatch:
```bash
        tag)   shift; _cmd_tag "$@" ;;
        untag) shift; _cmd_untag "$@" ;;
```

- [ ] **Step 2: Smoke**

```
bin/cc-harness add foo $HOME --tag math
bin/cc-harness tag foo +live -math
bin/cc-harness list --tag live
```
Expected: `foo` appears in the output of `list --tag live`.

- [ ] **Step 3: Commit**

```bash
git add bin/cc-harness
git commit -m "feat: cc-harness tag / untag"
```

---

## Phase G — Read-only subcommands

### Task 23: `cc-harness status` (with `--json`, `--tag`)

**Files:**
- Modify: `bin/cc-harness`

- [ ] **Step 1: Implement**

```bash
_cmd_status() {
    local json=0 tag=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json=1; shift ;;
            --tag)  tag="$2"; shift 2 ;;
            *) _die "$EXIT_USAGE" status "unknown flag: $1" ;;
        esac
    done
    local version="0.1.0"
    local claude_path; claude_path="$(command -v "$CCH_CLAUDE" 2>/dev/null || echo "(missing)")"
    local claude_ver=""
    [[ -x "$claude_path" ]] && claude_ver="$("$claude_path" --version 2>/dev/null | head -1)"
    local windows
    windows="$(tmux list-windows -t "$CCH_SESSION" -F '#I	#W	#{pane_current_path}	#{pane_pid}' 2>/dev/null || true)"

    if (( json )); then
        printf '{"version":"%s","session":"%s","claude":"%s","windows":[' \
            "$version" "$CCH_SESSION" "$claude_path"
        local first=1
        while IFS=$'\t' read -r idx wname cwd pid; do
            [[ -z "$wname" ]] && continue
            (( first )) || printf ","
            first=0
            printf '{"index":%s,"name":"%s","cwd":"%s","pid":%s}' \
                "$idx" "$wname" "$cwd" "$pid"
        done <<< "$windows"
        printf ']}\n'
        return 0
    fi

    printf "cc-harness %s  session=%s\n" "$version" "$CCH_SESSION"
    printf "claude: %s %s\n" "$claude_path" "$claude_ver"
    printf "host uptime: %s\n" "$(uptime -p 2>/dev/null || uptime)"
    printf "log: %s\n" "${CCH_LOG}"
    printf "\nwindows:\n"
    while IFS=$'\t' read -r idx wname cwd pid; do
        [[ -z "$wname" ]] && continue
        printf "  [%s] %-16s pid=%s  cwd=%s\n" "$idx" "$wname" "$pid" "$cwd"
    done <<< "$windows"
}
```

Dispatch:
```bash
        status) shift; _cmd_status "$@" ;;
```

- [ ] **Step 2: Smoke**

```
bin/cc-harness status
bin/cc-harness status --json | python3 -m json.tool
```
Expected: human and JSON output both render cleanly.

- [ ] **Step 3: Commit**

```bash
git add bin/cc-harness
git commit -m "feat: cc-harness status with --json and --tag"
```

---

### Task 24: `cc-harness doctor`

**Files:**
- Modify: `bin/cc-harness`
- Create: `tests/integration/doctor_pass_fail.bats`

- [ ] **Step 1: Implement**

```bash
_cmd_doctor() {
    local fail=0
    _check() {
        local name="$1" cmd="$2"
        if eval "$cmd" >/dev/null 2>&1; then
            printf "  ✓ %s\n" "$name"
        else
            printf "  ✗ %s\n" "$name"
            (( fail++ ))
        fi
    }
    printf "cc-harness doctor:\n"
    _check "tmux installed"             "command -v tmux"
    _check "tmux >= 3.0"                "tmux -V | awk '{print \$2}' | tr -d '[:alpha:]' | awk '{exit !(\$1+0 >= 3.0)}'"
    _check "claude binary on PATH"      "command -v $CCH_CLAUDE"
    _check "projects.conf parseable"    "[[ -f $CCH_CONF ]] && _projects >/dev/null"
    _check "every project path exists"  "_doctor_paths"
    _check "TERM supports 256color"     "[[ \$TERM == *256* ]] || tput colors | awk '{exit !(\$1>=256)}'"
    _check "fzf available (optional)"   "command -v fzf"
    if [[ -d "$HOME/cc-harness" && "$CCH_CONF" != "$HOME/cc-harness/projects.conf" ]]; then
        printf "  ⚠ legacy ~/cc-harness/ still present — safe to remove now\n"
    fi
    return "$fail"
}
_doctor_paths() {
    while IFS= read -r line; do
        eval "$(_lib_parse "$line" 2>/dev/null)" || continue
        local p; p="$(_lib_resolve_path "$path")"
        [[ -d "$p" ]] || return 1
    done < <(grep -vE '^\s*(#|$)' "$CCH_CONF")
    return 0
}
```

- [ ] **Step 2: Test**

```bash
@test "doctor: clean env returns 0" {
    mkdir -p "$XDG_CONFIG_HOME/cc-harness"
    echo "h = $HOME" > "$XDG_CONFIG_HOME/cc-harness/projects.conf"
    run_cch doctor
    [ "$status" -eq 0 ]
}

@test "doctor: missing claude returns nonzero" {
    export CCH_CLAUDE="$BATS_TEST_TMPDIR/nope"
    run_cch doctor
    [ "$status" -gt 0 ]
}
```

- [ ] **Step 3: Run + commit**

```bash
tests/bats/bin/bats tests/integration/doctor_pass_fail.bats
git add bin/cc-harness tests/integration/doctor_pass_fail.bats
git commit -m "feat: cc-harness doctor"
```

---

### Task 25: `cc-harness logs <label>`

**Files:**
- Modify: `bin/cc-harness`

- [ ] **Step 1: Implement**

```bash
_cmd_logs() {
    local label="${1:-}"
    [[ -n "$label" ]] || _die "$EXIT_USAGE" logs "usage: logs <label>"
    tmux list-windows -t "$CCH_SESSION" -F '#W' 2>/dev/null \
        | grep -qx -- "$label" \
        || _die "$EXIT_TMUX" logs "no window named $label"
    tmux capture-pane -t "$CCH_SESSION:$label" -p -S -3000
}
```

Dispatch:
```bash
        logs) shift; _cmd_logs "$@" ;;
```

- [ ] **Step 2: Commit**

```bash
git add bin/cc-harness
git commit -m "feat: cc-harness logs <label>"
```

---

### Task 26: `cc-harness which <label>`

**Files:**
- Modify: `bin/cc-harness`

- [ ] **Step 1: Implement**

```bash
_cmd_which() {
    local label="${1:-}"
    [[ -n "$label" ]] || _die "$EXIT_USAGE" which "usage: which <label>"
    local line; line="$(_lookup_project "$label")" \
        || _die "$EXIT_CONFIG" which "no such label: $label"
    eval "$(_lib_parse "$line")"
    _lib_resolve_path "$path"; printf "\n"
}
```

Dispatch:
```bash
        which) shift; _cmd_which "$@" ;;
```

- [ ] **Step 2: Smoke**

```
cd "$(bin/cc-harness which home)"
```
Expected: `cd` succeeds.

- [ ] **Step 3: Commit**

```bash
git add bin/cc-harness
git commit -m "feat: cc-harness which <label>"
```

---

## Phase H — Independent attachment

### Task 27: `cc-harness attach <label>` with grouped session

**Files:**
- Modify: `bin/cc-harness`
- Create: `tests/integration/multi_attach.bats`

- [ ] **Step 1: Write test**

```bash
#!/usr/bin/env bats
load '../test_helper.bash'

setup() {
    setup_test_env
    mkdir -p "$XDG_CONFIG_HOME/cc-harness"
    echo "alpha = $HOME" > "$XDG_CONFIG_HOME/cc-harness/projects.conf"
}
teardown() { teardown_test_env; }

@test "attach <label>: creates a grouped session" {
    "$CCH_BIN" attach &
    sleep 0.3
    "$CCH_BIN" new alpha
    sleep 0.3
    # Spawn an attached client in a subshell — emulate: tmux attach to grouped session.
    "$CCH_BIN" attach alpha &
    sleep 0.3
    run tmux $TMUX_TEST_FLAGS list-sessions -F '#S'
    [[ "$output" =~ cc-harness-view ]]
}
```

- [ ] **Step 2: Refactor `_cmd_attach` to take an optional label**

```bash
_cmd_attach() {
    local label="${1:-}"
    _lib_paths
    _lib_migrate

    [[ -f "$CCH_CONF" ]] || _seed_conf

    if ! tmux has-session -t "$CCH_SESSION" 2>/dev/null; then
        tmux new-session -d -s "$CCH_SESSION" -n menu \
            "exec '$CCH_SELF' menu"
        tmux set-option -t "$CCH_SESSION" status-style "bg=colour236,fg=colour250"
        tmux set-option -t "$CCH_SESSION" status-left  "#[bold] cc-harness #[default]│ "
        tmux set-option -t "$CCH_SESSION" status-right "#(date +%H:%M) "
        tmux set-option -t "$CCH_SESSION" mouse on
    else
        if ! tmux list-windows -t "$CCH_SESSION" -F '#W' 2>/dev/null | grep -qx menu; then
            tmux new-window -t "$CCH_SESSION:0" -n menu \
                "exec '$CCH_SELF' menu" 2>/dev/null \
                || tmux new-window -t "$CCH_SESSION:" -n menu \
                       "exec '$CCH_SELF' menu"
        fi
    fi

    # Stale-window detection.
    while IFS=$'\t' read -r idx wname pid; do
        [[ "$wname" == menu || "$wname" == \[dead\]* ]] && continue
        kill -0 "$pid" 2>/dev/null \
            || tmux rename-window -t "$CCH_SESSION:$idx" "[dead] $wname"
    done < <(tmux list-windows -t "$CCH_SESSION" -F '#I	#W	#{pane_pid}' 2>/dev/null)

    if [[ -n "$label" ]]; then
        # Independent client view via grouped session.
        local view="cc-harness-view-$$-$label"
        tmux new-session -d -t "$CCH_SESSION" -s "$view" 2>/dev/null || true
        tmux set-option -t "$view" destroy-unattached on 2>/dev/null || true
        if [[ -n "${TMUX:-}" ]]; then
            tmux switch-client -t "$view" \; select-window -t "$view:$label"
        else
            tmux attach-session -t "$view" \; select-window -t "$view:$label"
        fi
        return 0
    fi

    if [[ -n "${TMUX:-}" ]]; then
        tmux switch-client -t "$CCH_SESSION"
    else
        tmux attach-session -t "$CCH_SESSION"
    fi
}
```

Dispatch:
```bash
        attach|"") shift 2>/dev/null || true; _cmd_attach "${1:-}" ;;
```

- [ ] **Step 3: Run test — expected PASS**

Run: `tests/bats/bin/bats tests/integration/multi_attach.bats`
Expected: 1 passing.

- [ ] **Step 4: Commit**

```bash
git add bin/cc-harness tests/integration/multi_attach.bats
git commit -m "feat: cc-harness attach <label> via grouped tmux session"
```

---

## Phase I — Polish, completions, version, help

### Task 28: `cc-harness completion <bash|zsh|fish>`

**Files:**
- Modify: `bin/cc-harness`

- [ ] **Step 1: Implement**

```bash
_cmd_completion() {
    case "${1:-}" in
        bash) _emit_bash_completion ;;
        zsh)  _emit_zsh_completion ;;
        fish) _emit_fish_completion ;;
        *) _die "$EXIT_USAGE" completion "usage: completion <bash|zsh|fish>" ;;
    esac
}

_emit_bash_completion() {
cat <<'BASHEOF'
# cc-harness bash completion
_cc_harness() {
    local cur prev cmds
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cmds="attach new kill list add remove rename tag untag status doctor logs which completion install uninstall version --version --help -h"
    if [[ "$COMP_CWORD" -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$cmds" -- "$cur") )
        return 0
    fi
    case "$prev" in
        new|kill|logs|which|rename|remove|tag|untag)
            local labels
            labels=$(cc-harness list 2>/dev/null | awk 'NR>1 {print $1}')
            COMPREPLY=( $(compgen -W "$labels" -- "$cur") )
            ;;
        --tag)
            local tags
            tags=$(cc-harness list --tags 2>/dev/null | awk '{sub(/^#/,"",$1); print $1}')
            COMPREPLY=( $(compgen -W "$tags" -- "$cur") )
            ;;
        completion)
            COMPREPLY=( $(compgen -W "bash zsh fish" -- "$cur") )
            ;;
    esac
}
complete -F _cc_harness cc-harness
BASHEOF
}

_emit_zsh_completion() {
cat <<'ZSHEOF'
#compdef cc-harness
_cc_harness() {
    local -a cmds
    cmds=(
        'attach:attach the harness session'
        'new:spawn a new claude session'
        'kill:kill an existing claude session'
        'list:list configured projects'
        'add:add a project'
        'remove:remove a project'
        'rename:rename a project'
        'tag:add/remove tags on a project'
        'untag:strip all tags from a project'
        'status:show running session status'
        'doctor:run environment checks'
        'logs:capture pane output for a project'
        'which:print resolved path of a project'
        'completion:emit shell completion'
        'version:print version'
    )
    if (( CURRENT == 2 )); then
        _describe 'command' cmds
    else
        case "$words[2]" in
            new|kill|logs|which|rename|remove|tag|untag)
                local -a labels
                labels=(${(f)"$(cc-harness list 2>/dev/null | awk 'NR>1 {print $1}')"})
                _describe 'project' labels ;;
            completion)
                _arguments '*:shell:(bash zsh fish)' ;;
        esac
    fi
}
_cc_harness "$@"
ZSHEOF
}

_emit_fish_completion() {
cat <<'FISHEOF'
# cc-harness fish completion
function __cch_labels
    cc-harness list 2>/dev/null | awk 'NR>1 {print $1}'
end
function __cch_tags
    cc-harness list --tags 2>/dev/null | awk '{sub(/^#/,"",$1); print $1}'
end
complete -c cc-harness -f -n '__fish_use_subcommand' -a 'attach new kill list add remove rename tag untag status doctor logs which completion version'
complete -c cc-harness -n '__fish_seen_subcommand_from new kill logs which rename remove tag untag' -a '(__cch_labels)'
complete -c cc-harness -l tag -a '(__cch_tags)'
complete -c cc-harness -n '__fish_seen_subcommand_from completion' -a 'bash zsh fish'
FISHEOF
}
```

Dispatch:
```bash
        completion) shift; _cmd_completion "$@" ;;
```

- [ ] **Step 2: Smoke**

```
bin/cc-harness completion bash > /tmp/cch.bash && bash -n /tmp/cch.bash
bin/cc-harness completion zsh  > /tmp/cch.zsh
bin/cc-harness completion fish > /tmp/cch.fish && fish -n /tmp/cch.fish 2>&1
```
Expected: all syntax-clean.

- [ ] **Step 3: Commit**

```bash
git add bin/cc-harness
git commit -m "feat: cc-harness completion bash|zsh|fish"
```

---

### Task 29: `--version` and `version` subcommand

**Files:**
- Modify: `bin/cc-harness`

- [ ] **Step 1: Add a `CCH_VERSION` constant near the top**

```bash
readonly CCH_VERSION="0.1.0"
```

- [ ] **Step 2: Add dispatch entries**

```bash
        version|--version|-V)
            local sha=""
            if command -v git >/dev/null && [[ -d "$REPO_ROOT/.git" ]]; then
                sha="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null)"
            fi
            printf "cc-harness %s%s\n" "$CCH_VERSION" "${sha:+ ($sha)}"
            ;;
```

- [ ] **Step 3: Smoke**

Run: `bin/cc-harness --version`
Expected: `cc-harness 0.1.0 (<sha>)`.

- [ ] **Step 4: Commit**

```bash
git add bin/cc-harness
git commit -m "feat: --version / version with optional git SHA"
```

---

### Task 30: Per-subcommand `--help` with examples

**Files:**
- Modify: `bin/cc-harness` (expand `_help`, add `_help_<subcmd>`)

- [ ] **Step 1: Replace `_help` with dispatcher + per-subcommand pages**

```bash
_help() {
    local sub="${1:-}"
    case "$sub" in
        ""|--help|-h) _help_main ;;
        new)        _help_new ;;
        kill)       _help_kill ;;
        list)       _help_list ;;
        add)        _help_add ;;
        remove)     _help_remove ;;
        rename)     _help_rename ;;
        tag|untag)  _help_tag ;;
        status)     _help_status ;;
        doctor)     _help_doctor ;;
        logs)       _help_logs ;;
        which)      _help_which ;;
        attach)     _help_attach ;;
        completion) _help_completion ;;
        *) printf "cc-harness: no help for: %s\n" "$sub" >&2; return 2 ;;
    esac
}

_help_main() {
cat <<EOF
cc-harness $CCH_VERSION — Claude Code multi-session launcher

Usage: cc-harness [-v|-q] [--no-color] <command> [args]

Commands:
  attach [<label>]         attach (or attach to a single session view)
  new [<label>] [--fresh|--switch]   spawn or switch to a session
  kill [--all] [--tag T] [--dry-run] kill a session
  list [--tag T] [--tags]  show projects (or unique tags)
  add <label> <path> [--flags '...'] [--tag t]   add a project
  remove <label> [--dry-run]
  rename <old> <new>
  tag <label> +foo -bar
  untag <label>
  status [--json] [--tag T]
  doctor                   run environment checks
  logs <label>             capture last 3000 lines from a session pane
  which <label>            print resolved path
  completion <shell>       emit completion script
  version | --version
  <subcmd> --help          per-subcommand help

Configuration: \$XDG_CONFIG_HOME/cc-harness/projects.conf
Environment:   CCH_HOME, CCH_FLAGS, CCH_CLAUDE, CCH_SESSION, NO_COLOR
Docs:          man cc-harness   |   https://github.com/alejandro-soto-franco/cc-harness
EOF
}

_help_new() {
cat <<'EOF'
cc-harness new [<label>] [--fresh | --switch]

Spawn a new claude session, or switch to an existing one.

Examples:
  cc-harness new                  # interactive picker
  cc-harness new polybius         # spawn or switch
  cc-harness new polybius --fresh # always spawn a sibling (polybius-2, ...)
  cc-harness new polybius --switch  # only switch; error if no window
EOF
}

_help_attach() {
cat <<'EOF'
cc-harness attach [<label>]

Attach to the harness session. With <label>, open an isolated client view
focused on that session via a grouped tmux session (independent window
pointer per terminal).

Examples:
  cc-harness attach
  cc-harness attach polybius     # this terminal stays on polybius regardless
                                 # of what other terminals do
EOF
}

_help_kill() {
cat <<'EOF'
cc-harness kill [--all] [--tag TAG] [--dry-run]

Pick a window to kill, or kill in bulk by tag.

Examples:
  cc-harness kill                # interactive picker
  cc-harness kill --tag live --dry-run
  cc-harness kill --all
EOF
}

_help_list() {
cat <<'EOF'
cc-harness list [--tag TAG] [--tags]

Print configured projects, optionally filtered by tag.
--tags prints unique tags with counts instead of the project table.

Examples:
  cc-harness list
  cc-harness list --tag math
  cc-harness list --tags
EOF
}

_help_add() {
cat <<'EOF'
cc-harness add <label> <path> [--flags 'STR'] [--tag TAG]... [--dry-run]

Append a row to projects.conf.

Examples:
  cc-harness add polybius ~/Polybius
  cc-harness add polybius ~/Polybius --flags '--model opus' --tag live --tag rust
EOF
}

_help_remove() {
cat <<'EOF'
cc-harness remove <label> [--dry-run]

Remove the row for <label> from projects.conf.

Examples:
  cc-harness remove polybius
  cc-harness remove polybius --dry-run
EOF
}

_help_rename() {
cat <<'EOF'
cc-harness rename <old> <new>

Rename the projects.conf entry, and rename the live tmux window if present.

Examples:
  cc-harness rename polybius poly
EOF
}

_help_tag() {
cat <<'EOF'
cc-harness tag <label> +TAG -TAG ...
cc-harness untag <label>

Add or remove tags on a project. untag strips all tags from a row.

Examples:
  cc-harness tag polybius +live +rust -experimental
  cc-harness untag polybius
EOF
}

_help_status() {
cat <<'EOF'
cc-harness status [--json] [--tag TAG]

Print harness version, claude binary, host uptime, and active sessions.

Examples:
  cc-harness status
  cc-harness status --json | jq .
  cc-harness status --tag live
EOF
}

_help_doctor() {
cat <<'EOF'
cc-harness doctor

Run environment checks: tmux installed and >= 3.0, claude on PATH,
projects.conf parseable, every project path exists, terminal capable,
fzf optional. Exit code = number of failures.

Examples:
  cc-harness doctor
EOF
}

_help_logs() {
cat <<'EOF'
cc-harness logs <label>

Print the last 3000 lines from the named session's pane to stdout.

Examples:
  cc-harness logs polybius
  cc-harness logs polybius | grep ERROR
EOF
}

_help_which() {
cat <<'EOF'
cc-harness which <label>

Print the resolved (~ expanded) filesystem path for a project label.

Examples:
  cd "$(cc-harness which polybius)"
EOF
}

_help_completion() {
cat <<'EOF'
cc-harness completion <bash|zsh|fish>

Emit a shell completion script to stdout.

Examples:
  cc-harness completion bash > /etc/bash_completion.d/cc-harness
  cc-harness completion zsh  > ~/.zsh/completions/_cc-harness
  cc-harness completion fish > ~/.config/fish/completions/cc-harness.fish
EOF
}
```

- [ ] **Step 2: Wire `<subcmd> --help` through dispatch**

In each `_cmd_<name>`, at top of arg-parsing:
```bash
    [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && { _help <subcmd>; return 0; }
```

- [ ] **Step 3: Smoke**

```
bin/cc-harness --help
bin/cc-harness new --help
```
Expected: both print formatted help.

- [ ] **Step 4: Commit**

```bash
git add bin/cc-harness
git commit -m "feat: per-subcommand --help with examples"
```

---

### Task 31: New tmux keybinds (`prefix + 0` rebind, `prefix + N`)

**Files:**
- Modify: `bin/cc-harness` (`_cmd_attach` session-creation block)

- [ ] **Step 1: Add bindings during session bootstrap**

In `_cmd_attach`, inside the `if ! tmux has-session ... ; then` block, after the `set-option` lines, add:

```bash
        tmux bind-key -T prefix 0 \
            "if-shell '! tmux list-windows -F \"#W\" | grep -qx menu' \
            'new-window -t :=0 -n menu \"exec $CCH_SELF menu\"' \\\; \
            select-window -t :=0"
        tmux bind-key -T prefix N run-shell "$CCH_SELF new"
```

- [ ] **Step 2: Add SIGINT/SIGTERM trap to the menu loop**

In `_cmd_menu`, immediately after `_cmd_menu() {`, add:

```bash
    trap '_redraw_menu=1' INT TERM
    local _redraw_menu=0
```

Inside the `while true; do` body, replace `clear` with:

```bash
        if (( _redraw_menu )); then _redraw_menu=0; fi
        clear
```

Result: Ctrl-C inside fzf no longer leaves the terminal in a half-rendered state — the loop continues and redraws.

- [ ] **Step 3: Manual verification**

Detach + re-attach. From any window:
- `Ctrl-b 0` should bring you to the menu (and recreate it if it was killed).
- `Ctrl-b N` (capital) should open the project picker.
- Ctrl-C inside the menu's fzf prompt should redraw the menu cleanly instead of dropping you to a broken shell.

- [ ] **Step 4: Commit**

```bash
git add bin/cc-harness
git commit -m "feat: prefix+0 self-healing rebind, prefix+N picker, INT/TERM trap"
```

---

### Task 32: Help-output snapshot tests

**Files:**
- Create: `tests/unit/help_output.bats`

- [ ] **Step 1: Write tests**

```bash
#!/usr/bin/env bats
load '../test_helper.bash'

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "--help mentions every documented subcommand" {
    run "$CCH_BIN" --help
    [ "$status" -eq 0 ]
    for c in attach new kill list add remove rename tag untag status doctor logs which completion; do
        [[ "$output" =~ $c ]] || { echo "missing: $c"; return 1; }
    done
}

@test "--version prints semver" {
    run "$CCH_BIN" --version
    [[ "$output" =~ ^cc-harness\ 0\.[0-9]+\.[0-9]+ ]]
}

@test "subcmd --help works for every subcmd" {
    for c in new kill list add remove rename tag status doctor logs which attach completion; do
        run "$CCH_BIN" "$c" --help
        [ "$status" -eq 0 ] || { echo "fail: $c"; return 1; }
    done
}
```

- [ ] **Step 2: Run + commit**

```bash
tests/bats/bin/bats tests/unit/help_output.bats
git add tests/unit/help_output.bats
git commit -m "test: help output snapshots"
```

---

## Phase J — Close-out

### Task 33: shellcheck pass

**Files:**
- Modify: `bin/cc-harness` (any shellcheck warnings)
- Create: `.shellcheckrc`

- [ ] **Step 1: Add `.shellcheckrc`**

```
external-sources=true
shell=bash
```

- [ ] **Step 2: Run shellcheck**

Run: `shellcheck -x bin/cc-harness`
Expected: clean. Fix every warning by editing the script directly. Acceptable to disable a specific warning inline only with a one-line `# shellcheck disable=SCxxxx — <reason>` comment.

- [ ] **Step 3: Commit**

```bash
git add .shellcheckrc bin/cc-harness
git commit -m "chore: shellcheck-clean"
```

---

### Task 34: Final regression run

**Files:** none

- [ ] **Step 1: Run full test suite**

Run: `tests/bats/bin/bats tests/`
Expected: every test passes.

- [ ] **Step 2: Run doctor against the user's actual config**

Run: `bin/cc-harness doctor`
Expected: zero failures (or only the legacy-dir warning).

- [ ] **Step 3: Tag a working snapshot**

```bash
git tag v0.1.0-rc1 -m "v0.1.0-rc1 — core complete, packaging next"
```

- [ ] **Step 4: Commit (if any cleanups landed)**

```bash
git status
# If clean, no commit needed. Otherwise:
git add -A && git commit -m "chore: pre-rc1 cleanups"
```

---

## Spec coverage matrix

| Spec section | Implementing tasks |
|---|---|
| §2 file layout (repo + installed) | 1 |
| §3.1 command table | 14, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30 |
| §3.2 global flags | 11, 30 |
| §3.3 exit codes | 10 (constants), used throughout |
| §3.4 multi-instance | 16 |
| §3.5 independent attach | 27 |
| §3.6 tags + filters | 8 (parser), 18 (list), 22 (tag/untag), 17 (kill --tag), 23 (status --tag) |
| §4.1 self-healing | 4 (menu respawn), 31 (keybind), 15 (stale window) |
| §4.2 preflight | 13, 14 |
| §4.3 error handling | 10 |
| §4.4 lockfile | 12, used in 19/20/21/22 |
| §4.5 logging | 11 |
| §4.6 signals | 31 (INT/TERM trap in menu loop) |
| §5.1 path resolution | 5 |
| §5.2 migration trigger | 7 |
| §5.3 state files | 5, 11 |
| §5.4 config format | 8 |
| §5.5 validation | 9 |
| §5.6 env vars | 5, 11 |
| §7.1 bats layout | 2, plus per-task tests throughout |
| §7.2 isolation | 2 |
| §7.3 coverage target | satisfied per task |
| §8.2 LICENSE / SPDX | 1 |

## Out of scope (Plan 2)

- §6 Packaging (Makefile, install.sh, Homebrew tap, Copr, AUR, deb/rpm, GH release CI).
- §7.4–7.6 (lint and format CI, pre-commit, GH Actions matrix).
- §8 OSS hygiene apart from LICENSE/SPDX (README, CHANGELOG, CONTRIBUTING, SECURITY, COC, issue/PR templates, dependabot, man page source).

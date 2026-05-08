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
        elapsed=$((elapsed + 1))
    done
}

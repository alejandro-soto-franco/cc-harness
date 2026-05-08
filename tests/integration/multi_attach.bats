#!/usr/bin/env bats
load '../test_helper.bash'

setup() {
    setup_test_env
    mkdir -p "$XDG_CONFIG_HOME/cc-harness"
    echo "alpha = $HOME" > "$XDG_CONFIG_HOME/cc-harness/projects.conf"
    # Pre-stage the session.
    tmux $TMUX_TEST_FLAGS new-session -d -s "$CCH_SESSION" -n menu "exec sleep 9999"
    wait_for_window menu 5
}
teardown() { teardown_test_env; }

@test "attach <label>: creates a grouped session" {
    # Spawn the alpha window via cc-harness new (uses _spawn).
    env TMUX_FLAGS="$TMUX_TEST_FLAGS" "$CCH_BIN" new alpha
    sleep 0.3

    # Run cc-harness attach <label>. The actual `tmux attach-session` at the
    # end will fail in this env (no tty); that's fine — we only need the
    # `new-session -t` for grouping to have run before that point.
    run env TMUX_FLAGS="$TMUX_TEST_FLAGS" "$CCH_BIN" attach alpha

    # The grouped session name pattern is "cc-harness-view-<pid>-<label>".
    run tmux $TMUX_TEST_FLAGS list-sessions -F '#S'
    [[ "$output" == *"cc-harness-view"* ]]
}

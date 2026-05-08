#!/usr/bin/env bats
load '../test_helper.bash'

setup() {
    setup_test_env
    export TMUX_FLAGS="$TMUX_TEST_FLAGS"
    mkdir -p "$XDG_CONFIG_HOME/cc-harness"
    echo "alpha = $HOME" > "$XDG_CONFIG_HOME/cc-harness/projects.conf"
}
teardown() { teardown_test_env; }

@test "attach <label>: creates a grouped session" {
    "$CCH_BIN" attach >/dev/null 2>&1 &
    wait_for_window menu 5
    "$CCH_BIN" new alpha
    sleep 0.3
    "$CCH_BIN" attach alpha >/dev/null 2>&1 &
    sleep 0.3
    run tmux $TMUX_TEST_FLAGS list-sessions -F '#S'
    [[ "$output" == *"cc-harness-view"* ]]
}

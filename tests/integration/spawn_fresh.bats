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

@test "new <label> default: switches to existing window" {
    env TMUX_FLAGS="$TMUX_TEST_FLAGS" "$CCH_BIN" new alpha
    sleep 0.3
    env TMUX_FLAGS="$TMUX_TEST_FLAGS" "$CCH_BIN" new alpha
    sleep 0.3
    run tmux $TMUX_TEST_FLAGS list-windows -t "$CCH_SESSION" -F '#W'
    [ "$(echo "$output" | grep -c '^alpha$')" -eq 1 ]
}

@test "new <label> --fresh: creates alpha-2" {
    env TMUX_FLAGS="$TMUX_TEST_FLAGS" "$CCH_BIN" new alpha
    sleep 0.3
    env TMUX_FLAGS="$TMUX_TEST_FLAGS" "$CCH_BIN" new alpha --fresh
    sleep 0.3
    run tmux $TMUX_TEST_FLAGS list-windows -t "$CCH_SESSION" -F '#W'
    [[ "$output" == *"alpha-2"* ]]
}

@test "new <label> --switch with no existing window: errors" {
    run env TMUX_FLAGS="$TMUX_TEST_FLAGS" "$CCH_BIN" new alpha --switch
    [ "$status" -eq 4 ]
}

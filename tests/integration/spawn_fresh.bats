#!/usr/bin/env bats
load '../test_helper.bash'

setup() {
    setup_test_env
    export TMUX_FLAGS="$TMUX_TEST_FLAGS"   # so direct $CCH_BIN calls share the test socket
    mkdir -p "$XDG_CONFIG_HOME/cc-harness"
    echo "alpha = $HOME" > "$XDG_CONFIG_HOME/cc-harness/projects.conf"
    "$CCH_BIN" attach >/dev/null 2>&1 &
    wait_for_window menu 5
}
teardown() { teardown_test_env; }

@test "new <label> default: switches to existing window" {
    "$CCH_BIN" new alpha
    "$CCH_BIN" new alpha
    run tmux $TMUX_TEST_FLAGS list-windows -t "$CCH_SESSION" -F '#W'
    [ "$(echo "$output" | grep -c '^alpha$')" -eq 1 ]
}

@test "new <label> --fresh: creates alpha-2" {
    "$CCH_BIN" new alpha
    "$CCH_BIN" new alpha --fresh
    run tmux $TMUX_TEST_FLAGS list-windows -t "$CCH_SESSION" -F '#W'
    [[ "$output" == *"alpha-2"* ]]
}

@test "new <label> --switch with no existing window: errors" {
    run "$CCH_BIN" new alpha --switch
    [ "$status" -eq 4 ]
}

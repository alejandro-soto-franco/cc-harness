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

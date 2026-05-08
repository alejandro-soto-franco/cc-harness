#!/usr/bin/env bats
load '../test_helper.bash'

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "attach recreates the menu window when it has been killed" {
    # Pre-stage: manually create the cc-harness session as if it had been
    # launched normally, but use a long-running placeholder for the menu
    # window instead of cc-harness's interactive menu loop (which can't
    # run inside bats — no tty, no fzf input).
    tmux $TMUX_TEST_FLAGS new-session -d -s "$CCH_SESSION" -n menu "exec sleep 9999"
    wait_for_window menu 5

    # Make sure cc-harness has a parseable config so _cmd_attach doesn't
    # bail early.
    mkdir -p "$XDG_CONFIG_HOME/cc-harness"
    : > "$XDG_CONFIG_HOME/cc-harness/projects.conf"

    # Sanity: menu window exists.
    run tmux $TMUX_TEST_FLAGS list-windows -t "$CCH_SESSION" -F '#W'
    [[ "$output" == *menu* ]]

    # Simulate today's failure mode: kill the menu window.
    tmux $TMUX_TEST_FLAGS kill-window -t "$CCH_SESSION:menu"
    run tmux $TMUX_TEST_FLAGS list-windows -t "$CCH_SESSION" -F '#W'
    [[ "$output" != *menu* ]]

    # Re-invoke cc-harness attach. The fix should detect the missing menu
    # window and recreate it. The actual `tmux attach-session` call at the
    # end will fail in this environment (no tty); that's fine — we only
    # care that the recreation logic ran before the attach call.
    run env TMUX_FLAGS="$TMUX_TEST_FLAGS" "$CCH_BIN" attach

    # Wait for the window to come back. Use the helper.
    wait_for_window menu 5

    # Assert window 0 is named "menu" again.
    run tmux $TMUX_TEST_FLAGS list-windows -t "$CCH_SESSION" -F '#I:#W'
    [[ "$output" == 0:menu* ]]
}

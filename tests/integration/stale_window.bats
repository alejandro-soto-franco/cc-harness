#!/usr/bin/env bats
load '../test_helper.bash'

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "stale window is renamed to [dead] <label> on attach" {
    # Pre-stage the session with a long-lived menu window.
    tmux $TMUX_TEST_FLAGS new-session -d -s "$CCH_SESSION" -n menu "exec sleep 9999"
    wait_for_window menu 5

    mkdir -p "$XDG_CONFIG_HOME/cc-harness"
    echo "deadproj = $HOME" > "$XDG_CONFIG_HOME/cc-harness/projects.conf"

    # Enable remain-on-exit globally so the window stays after the pane dies.
    tmux $TMUX_TEST_FLAGS set-option -t "$CCH_SESSION" -g remain-on-exit on

    # Spawn a window whose process exits immediately (simulates dead claude).
    tmux $TMUX_TEST_FLAGS new-window -t "$CCH_SESSION:" -n deadproj "exec true"

    # Wait for the pane to die (remain-on-exit keeps the window).
    local elapsed=0
    while tmux $TMUX_TEST_FLAGS list-windows -t "$CCH_SESSION" -F '#W' 2>/dev/null \
            | grep -qx deadproj; do
        local pid
        pid="$(tmux $TMUX_TEST_FLAGS list-windows -t "$CCH_SESSION" \
            -F '#{window_name}	#{pane_pid}' 2>/dev/null \
            | awk -F'\t' '$1=="deadproj"{print $2}')"
        # Once the PID is gone the pane is dead; break out.
        if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
        (( elapsed >= 30 )) && break
        sleep 0.1
        (( elapsed++ ))
    done

    # Invoke attach (non-interactive — TMUX is set so it tries switch-client,
    # which will fail gracefully in a non-client context; that's fine, we only
    # care that the rename happened before the attach attempt).
    TMUX=fake run env TMUX_FLAGS="$TMUX_TEST_FLAGS" TMUX=fake "$CCH_BIN" attach 2>/dev/null || true

    run tmux $TMUX_TEST_FLAGS list-windows -t "$CCH_SESSION" -F '#W'
    [[ "$output" == *"[dead] deadproj"* ]]
}

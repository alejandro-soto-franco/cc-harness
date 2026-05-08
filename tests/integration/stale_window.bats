#!/usr/bin/env bats
load '../test_helper.bash'

setup() {
    setup_test_env
    export TMUX_FLAGS="$TMUX_TEST_FLAGS"
}
teardown() { teardown_test_env; }

@test "stale window is renamed to [dead] <label> on attach" {
    cat > "$BATS_TEST_TMPDIR/quick-stub.sh" <<'EOF'
#!/usr/bin/env bash
# Brief sleep so cc-harness has time to set remain-on-exit before the
# pane exits. Mimics a real claude crash (which has at least startup
# latency before any error).
sleep 0.3
exit 0
EOF
    chmod +x "$BATS_TEST_TMPDIR/quick-stub.sh"
    export CCH_CLAUDE="$BATS_TEST_TMPDIR/quick-stub.sh"

    mkdir -p "$XDG_CONFIG_HOME/cc-harness"
    echo "deadproj = $HOME" > "$XDG_CONFIG_HOME/cc-harness/projects.conf"

    "$CCH_BIN" attach >/dev/null 2>&1 &
    wait_for_window menu 5
    "$CCH_BIN" new deadproj || true
    sleep 1.0

    "$CCH_BIN" attach || true
    run tmux $TMUX_TEST_FLAGS list-windows -t "$CCH_SESSION" -F '#W'
    [[ "$output" == *"[dead] deadproj"* ]]
}

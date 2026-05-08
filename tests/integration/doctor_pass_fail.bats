#!/usr/bin/env bats
load '../test_helper.bash'

setup() { setup_test_env; }
teardown() { teardown_test_env; }

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

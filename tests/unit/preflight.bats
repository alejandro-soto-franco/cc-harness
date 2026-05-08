#!/usr/bin/env bats
load '../test_helper.bash'

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "preflight: missing claude binary -> exit 5" {
    export CCH_CLAUDE="$BATS_TEST_TMPDIR/does-not-exist"
    run_cch _preflight-claude
    [ "$status" -eq 5 ]
    [[ "$output" == *"claude binary not found"* ]]
}

@test "preflight: present claude binary -> exit 0" {
    run_cch _preflight-claude
    [ "$status" -eq 0 ]
}

@test "preflight: tmux present and recent -> exit 0" {
    run_cch _preflight-tmux
    [ "$status" -eq 0 ]
}

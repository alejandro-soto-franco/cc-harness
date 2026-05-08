#!/usr/bin/env bats
load '../test_helper.bash'

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "migration: copies legacy projects.conf to XDG and writes marker" {
    mkdir -p "$HOME/cc-harness"
    echo "foo = /tmp/foo" > "$HOME/cc-harness/projects.conf"

    run_cch list
    [ "$status" -eq 0 ]

    [ -f "$XDG_CONFIG_HOME/cc-harness/projects.conf" ]
    [ -f "$XDG_STATE_HOME/cc-harness/.migrated-from-legacy" ]
    grep -q "foo = /tmp/foo" "$XDG_CONFIG_HOME/cc-harness/projects.conf"
}

@test "migration: prints one-time stderr notice" {
    mkdir -p "$HOME/cc-harness"
    echo "foo = /tmp/foo" > "$HOME/cc-harness/projects.conf"

    run --separate-stderr "$CCH_BIN" list
    [[ "$stderr" =~ "migrated config from" ]]
}

@test "migration: does NOT run when CCH_HOME is set" {
    mkdir -p "$HOME/cc-harness" "$HOME/custom"
    echo "foo = /tmp/foo" > "$HOME/cc-harness/projects.conf"
    echo "bar = /tmp/bar" > "$HOME/custom/projects.conf"
    export CCH_HOME="$HOME/custom"

    run_cch list
    [ ! -f "$XDG_CONFIG_HOME/cc-harness/projects.conf" ]
}

@test "migration: idempotent — second run skips silently" {
    mkdir -p "$HOME/cc-harness"
    echo "foo = /tmp/foo" > "$HOME/cc-harness/projects.conf"

    run_cch list  # first run migrates
    run_cch list  # second run: marker present, no notice
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "migrated config from" ]]
}

@test "migration: legacy directory is left in place" {
    mkdir -p "$HOME/cc-harness"
    echo "foo = /tmp/foo" > "$HOME/cc-harness/projects.conf"
    run_cch list
    [ -f "$HOME/cc-harness/projects.conf" ]
}

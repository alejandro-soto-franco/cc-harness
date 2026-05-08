#!/usr/bin/env bats
load '../test_helper.bash'

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "CCH_HOME wins over XDG and legacy" {
    mkdir -p "$HOME/custom"
    echo "foo = /tmp" > "$HOME/custom/projects.conf"
    export CCH_HOME="$HOME/custom"
    run_cch _debug-paths
    [[ "$output" == *"config=$HOME/custom/projects.conf"* ]]
}

@test "XDG wins over legacy when XDG file exists" {
    mkdir -p "$XDG_CONFIG_HOME/cc-harness" "$HOME/cc-harness"
    echo "foo = /tmp" > "$XDG_CONFIG_HOME/cc-harness/projects.conf"
    echo "bar = /tmp" > "$HOME/cc-harness/projects.conf"
    run_cch _debug-paths
    [[ "$output" == *"config=$XDG_CONFIG_HOME/cc-harness/projects.conf"* ]]
}

@test "legacy is used when XDG file absent" {
    mkdir -p "$HOME/cc-harness"
    echo "foo = /tmp" > "$HOME/cc-harness/projects.conf"
    run_cch _debug-paths
    [[ "$output" == *"config=$HOME/cc-harness/projects.conf"* ]]
}

@test "fresh install resolves to XDG default with no file yet" {
    run_cch _debug-paths
    [[ "$output" == *"config=$XDG_CONFIG_HOME/cc-harness/projects.conf"* ]]
}

#!/usr/bin/env bats
load '../test_helper.bash'

setup() {
    setup_test_env
    mkdir -p "$XDG_CONFIG_HOME/cc-harness"
    : > "$XDG_CONFIG_HOME/cc-harness/projects.conf"
}
teardown() { teardown_test_env; }

@test "add: appends a row" {
    run_cch add proj1 "$HOME"
    [ "$status" -eq 0 ]
    grep -q "^proj1 = $HOME" "$XDG_CONFIG_HOME/cc-harness/projects.conf"
}

@test "add: rejects duplicate label" {
    run_cch add proj1 "$HOME"
    run_cch add proj1 "$HOME"
    [ "$status" -eq 3 ]
}

@test "add: rejects non-existent path" {
    run_cch add proj1 /does/not/exist
    [ "$status" -eq 3 ]
}

@test "add: with flags and tags" {
    run_cch add proj1 "$HOME" --flags "--model opus" --tag live --tag math
    [ "$status" -eq 0 ]
    grep -q "proj1 = $HOME | --model opus" \
        "$XDG_CONFIG_HOME/cc-harness/projects.conf"
    grep -q "#live" "$XDG_CONFIG_HOME/cc-harness/projects.conf"
    grep -q "#math" "$XDG_CONFIG_HOME/cc-harness/projects.conf"
}

@test "add --dry-run: no write" {
    run_cch add proj1 "$HOME" --dry-run
    [ "$status" -eq 0 ]
    ! grep -q "^proj1" "$XDG_CONFIG_HOME/cc-harness/projects.conf"
}

@test "remove: drops a row" {
    "$CCH_BIN" add proj1 "$HOME"
    run_cch remove proj1
    [ "$status" -eq 0 ]
    ! grep -q "^proj1" "$XDG_CONFIG_HOME/cc-harness/projects.conf"
}

@test "remove: errors on missing label" {
    run_cch remove ghost
    [ "$status" -eq 3 ]
}

@test "remove --dry-run" {
    "$CCH_BIN" add proj1 "$HOME"
    run_cch remove proj1 --dry-run
    [ "$status" -eq 0 ]
    grep -q "^proj1" "$XDG_CONFIG_HOME/cc-harness/projects.conf"
}

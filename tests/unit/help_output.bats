#!/usr/bin/env bats
load '../test_helper.bash'

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "--help mentions every documented subcommand" {
    run "$CCH_BIN" --help
    [ "$status" -eq 0 ]
    for c in attach new kill list add remove rename tag untag status doctor logs which completion; do
        [[ "$output" == *"$c"* ]] || { echo "missing: $c"; return 1; }
    done
}

@test "--version prints semver" {
    run "$CCH_BIN" --version
    [[ "$output" =~ ^cc-harness\ 0\.[0-9]+\.[0-9]+ ]]
}

@test "subcmd --help works for every subcmd" {
    for c in new kill list add remove rename tag status doctor logs which attach completion; do
        run "$CCH_BIN" "$c" --help
        [ "$status" -eq 0 ] || { echo "fail: $c"; return 1; }
    done
}

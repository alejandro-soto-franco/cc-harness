#!/usr/bin/env bats
load '../test_helper.bash'

setup() { setup_test_env; }
teardown() { teardown_test_env; }

@test "label: alnum + dash + underscore allowed" {
    run "$CCH_BIN" _validate-label "foo-bar_1"
    [ "$status" -eq 0 ]
}

@test "label: empty rejected" {
    run "$CCH_BIN" _validate-label ""
    [ "$status" -eq 3 ]
}

@test "label: spaces rejected" {
    run "$CCH_BIN" _validate-label "foo bar"
    [ "$status" -eq 3 ]
}

@test "label: too long rejected (>32)" {
    run "$CCH_BIN" _validate-label "$(printf 'a%.0s' {1..33})"
    [ "$status" -eq 3 ]
}

@test "tag: alnum + dash + underscore allowed" {
    run "$CCH_BIN" _validate-tag "live-1"
    [ "$status" -eq 0 ]
}

@test "tag: too long rejected (>24)" {
    run "$CCH_BIN" _validate-tag "$(printf 'a%.0s' {1..25})"
    [ "$status" -eq 3 ]
}

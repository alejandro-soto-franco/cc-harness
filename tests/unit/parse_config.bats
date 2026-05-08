#!/usr/bin/env bats
load '../test_helper.bash'

setup() { setup_test_env; }
teardown() { teardown_test_env; }

parse_line() {
    "$CCH_BIN" _parse-line "$1"
}

@test "parse: bare label = path" {
    run parse_line "foo = /tmp/foo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"label=foo"* ]]
    [[ "$output" == *"path=/tmp/foo"* ]]
    [[ "$output" == *"flags="* ]]
    [[ "$output" == *"tags="* ]]
}

@test "parse: with flags" {
    run parse_line "foo = /tmp/foo | --model opus"
    [[ "$output" == *"flags=--model opus"* ]]
}

@test "parse: with tags" {
    run parse_line "foo = /tmp/foo #live #trading"
    [[ "$output" == *"tags=live trading"* ]]
}

@test "parse: with flags and tags" {
    run parse_line "foo = /tmp/foo | --model opus  #live #trading"
    [[ "$output" == *"flags=--model opus"* ]]
    [[ "$output" == *"tags=live trading"* ]]
}

@test "parse: ~ in path expanded later (parser preserves literal)" {
    run parse_line "home = ~"
    [[ "$output" == *"path=~"* ]]
}

@test "parse: multiple equals signs — split on first only" {
    run parse_line "weird = /tmp/foo=bar"
    [[ "$output" == *"path=/tmp/foo=bar"* ]]
}

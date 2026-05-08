#!/usr/bin/env bats
load '../test_helper.bash'

@test "bats harness boots" {
    [ "$(echo hello)" = "hello" ]
}

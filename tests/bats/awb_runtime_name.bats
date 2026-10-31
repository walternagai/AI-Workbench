#!/usr/bin/env bats
# M3: `awb runtime <cmd> <name>` must reject names that escape runtimes/.
# Before the fix, '..' passed the regex and runtimes/../install.sh resolved to
# the repo's installer, so sourcing it started the whole installation.
#
# Every case here is a rejection, so the installer is never reached. The
# runtime name is checked before safe_source, and the installer's banner must
# never appear in the output. HOME is redirected so nothing touches the real one.

setup() {
    AWB_CLI="${BATS_TEST_DIRNAME}/../../scripts/awb"
    export HOME
    HOME="$(mktemp -d)"
}

teardown() {
    rm -rf "$HOME"
}

@test "awb runtime: '..' is rejected and the installer is not sourced" {
    run "$AWB_CLI" runtime install ..
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid runtime name"* ]]
    [[ "$output" != *"Installer"* ]]
}

@test "awb runtime: '.' is rejected" {
    run "$AWB_CLI" runtime install .
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid runtime name"* ]]
}

@test "awb runtime: a name with a path separator is rejected" {
    run "$AWB_CLI" runtime install ../x
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid runtime name"* ]]
}

@test "awb runtime: a well-formed name with no runtime behind it is rejected as unknown" {
    run "$AWB_CLI" runtime install nao-existe
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown runtime"* ]]
}

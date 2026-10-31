#!/usr/bin/env bats
# `make test-python` chooses its pytest: the dedicated venv (AWB_TEST_VENV,
# default ~/venvs/awb-test) when it has one, otherwise whatever pytest is on
# PATH, as CI does. Asserted through `make -n`, which prints the command it
# would run, so nothing is executed and no test environment is needed.

setup() {
    REPO="${BATS_TEST_DIRNAME}/../.."
    FAKE="$(mktemp -d)"
    mkdir -p "${FAKE}/venv/bin" "${FAKE}/path"
    printf '#!/bin/sh\nexit 0\n' > "${FAKE}/venv/bin/pytest"
    printf '#!/bin/sh\nexit 0\n' > "${FAKE}/path/pytest"
    chmod +x "${FAKE}/venv/bin/pytest" "${FAKE}/path/pytest"
}

teardown() {
    rm -rf "$FAKE"
}

@test "test-python uses the venv's pytest when the venv exists" {
    run make -C "$REPO" -n test-python AWB_TEST_VENV="${FAKE}/venv"
    [ "$status" -eq 0 ]
    [[ "$output" == *"${FAKE}/venv/bin/pytest --cov"* ]]
}

@test "test-python falls back to the pytest on PATH when there is no venv" {
    run env PATH="${FAKE}/path:${PATH}" make -C "$REPO" -n test-python AWB_TEST_VENV="${FAKE}/absent"
    [ "$status" -eq 0 ]
    [[ "$output" == *"${FAKE}/path/pytest --cov"* ]]
    # The missing venv's pytest must not be the one chosen. (The bare word
    # "absent" can still appear in the install hint, so match the binary path.)
    [[ "$output" != *"absent/bin/pytest"* ]]
}

@test "test-python fails with the venv install hint when no pytest exists anywhere" {
    empty="${FAKE}/empty"
    mkdir -p "$empty"
    run env -i PATH="$empty" "$(command -v make)" -C "$REPO" test-python AWB_TEST_VENV="${FAKE}/absent"
    [ "$status" -ne 0 ]
    [[ "$output" == *"pytest not installed"* ]]
    [[ "$output" == *"python3 -m venv"* ]]
}

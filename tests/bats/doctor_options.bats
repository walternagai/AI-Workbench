#!/usr/bin/env bats
# M2: doctor.sh is deliberately `set -uo pipefail` without -e, so one failed
# check cannot stop the diagnosis. It sources detect.sh, and detect.sh used to
# turn -e on at the top level of the sourced file, which silently changed
# doctor's shell options. These tests fail if sourcing detect.sh changes them.

setup() {
    AWB_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    export AWB_ROOT
}

@test "sourcing detect.sh leaves errexit off in the caller" {
    run bash -c 'set -uo pipefail; source "$AWB_ROOT/detect.sh"; case $- in *e*) exit 1;; esac'
    [ "$status" -eq 0 ]
}

@test "a command substitution that fails does not abort a sourcing caller" {
    run bash -c 'set -uo pipefail; source "$AWB_ROOT/detect.sh"; out="$(false | head -1)"; echo reached'
    [ "$status" -eq 0 ]
    [[ "$output" == *"reached"* ]]
}

@test "detect.sh still runs with errexit when executed directly" {
    # The option is applied in the direct-execution branch, so the standalone
    # run keeps its fail-fast behaviour. Checked with a read-only grep: running
    # the real detection here would probe hardware and write reports/.
    grep -q '^    set -euo pipefail$' "${AWB_ROOT}/detect.sh"
}

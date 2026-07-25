#!/usr/bin/env bats
# Unit tests for the pure, deterministic parts of lib/downloader.sh — checksum
# verification only; the download paths do real network I/O and are out of
# scope for a unit suite. Run with:
#   bats tests/bats/lib_downloader.bats

setup() {
    export AWB_ROOT
    AWB_ROOT="$(mktemp -d)"
    source "${BATS_TEST_DIRNAME}/../../lib/colors.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/logger.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/utils.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/downloader.sh"

    test_file="${AWB_ROOT}/file.txt"
    printf 'hello world' > "$test_file"
    expected_sha="$(sha256sum "$test_file" | awk '{print $1}')"
}

teardown() {
    rm -rf "$AWB_ROOT"
}

@test "awb_verify_checksum: succeeds for a matching sha256" {
    run awb_verify_checksum "$test_file" "$expected_sha"
    [ "$status" -eq 0 ]
}

@test "awb_verify_checksum: fails for a mismatched sha256" {
    run awb_verify_checksum "$test_file" "0000000000000000000000000000000000000000000000000000000000000"
    [ "$status" -ne 0 ]
}

@test "awb_verify_checksum: is case-sensitive (sha256sum only ever emits lowercase)" {
    uppercase_sha="$(echo "$expected_sha" | tr '[:lower:]' '[:upper:]')"
    run awb_verify_checksum "$test_file" "$uppercase_sha"
    [ "$status" -ne 0 ]
}

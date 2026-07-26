#!/usr/bin/env bats
# Unit tests for the pure, deterministic parts of lib/downloader.sh — checksum
# verification and CLI resolution; the download paths themselves do real
# network I/O and are out of scope for a unit suite. Run with:
#   bats tests/bats/lib_downloader.bats

setup() {
    export AWB_ROOT
    AWB_ROOT="$(mktemp -d)"
    # Point the venv lookup at an empty directory for every test in this file.
    # Without this, _awb_hf_cli falls through to the real ~/venvs/core/bin/hf,
    # so the suite passed on a clean CI runner and failed on any machine where
    # AI-Workbench was actually installed — i.e. exactly the developers running
    # it. Tests that want a venv create one under this root themselves.
    export AWB_VENV_ROOT="${AWB_ROOT}/venvs"
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

# --- _awb_hf_cli ---------------------------------------------------------------
# Regression coverage for two failure modes that silently broke model
# downloads: preferring the deprecated `huggingface-cli` over `hf`, and not
# looking inside ~/venvs/core (which create_envs.sh populates but nothing
# adds to PATH).

# Creates a fake venv layout and neutralizes PATH lookups so only the venv
# fallback can resolve.
_stub_empty_path() { has_cmd() { return 1; }; }

@test "_awb_hf_cli: prefers hf over the deprecated huggingface-cli on PATH" {
    has_cmd() { [[ "$1" == "hf" || "$1" == "huggingface-cli" ]]; }
    run _awb_hf_cli
    [ "$status" -eq 0 ]
    [ "$output" = "hf" ]
}

@test "_awb_hf_cli: falls back to huggingface-cli when hf is absent" {
    has_cmd() { [[ "$1" == "huggingface-cli" ]]; }
    run _awb_hf_cli
    [ "$status" -eq 0 ]
    [ "$output" = "huggingface-cli" ]
}

@test "_awb_hf_cli: finds hf inside ~/venvs/core when nothing is on PATH" {
    _stub_empty_path
    export AWB_VENV_ROOT="${AWB_ROOT}/venvs"
    mkdir -p "${AWB_VENV_ROOT}/core/bin"
    touch "${AWB_VENV_ROOT}/core/bin/hf"
    chmod +x "${AWB_VENV_ROOT}/core/bin/hf"

    run _awb_hf_cli
    [ "$status" -eq 0 ]
    [ "$output" = "${AWB_VENV_ROOT}/core/bin/hf" ]
}

@test "_awb_hf_cli: prefers a PATH hf over the venv copy" {
    has_cmd() { [[ "$1" == "hf" ]]; }
    export AWB_VENV_ROOT="${AWB_ROOT}/venvs"
    mkdir -p "${AWB_VENV_ROOT}/core/bin"
    touch "${AWB_VENV_ROOT}/core/bin/hf"
    chmod +x "${AWB_VENV_ROOT}/core/bin/hf"

    run _awb_hf_cli
    [ "$status" -eq 0 ]
    [ "$output" = "hf" ]
}

@test "_awb_hf_cli: returns non-zero when no CLI exists anywhere" {
    _stub_empty_path
    export AWB_VENV_ROOT="${AWB_ROOT}/venvs-empty"
    run _awb_hf_cli
    [ "$status" -ne 0 ]
}

@test "_awb_hf_cli: ignores a non-executable venv file" {
    _stub_empty_path
    export AWB_VENV_ROOT="${AWB_ROOT}/venvs"
    mkdir -p "${AWB_VENV_ROOT}/core/bin"
    touch "${AWB_VENV_ROOT}/core/bin/hf"   # deliberately not chmod +x

    run _awb_hf_cli
    [ "$status" -ne 0 ]
}

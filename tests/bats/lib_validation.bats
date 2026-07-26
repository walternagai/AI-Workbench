#!/usr/bin/env bats
# Unit tests for lib/validation.sh — the preflight gate shared by install.sh
# and doctor.sh. These matter more than their size suggests: doctor.sh's
# Resources checks deliberately mirror the severities decided here (disk
# shortage is fatal, low RAM only degrades), so a change on this side silently
# desynchronises the two reports. Run with:
#   bats tests/bats/lib_validation.bats

setup() {
    export AWB_ROOT
    AWB_ROOT="$(mktemp -d)"
    STUB_BIN="$(mktemp -d)"
    export STUB_BIN

    source "${BATS_TEST_DIRNAME}/../../lib/colors.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/logger.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/utils.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/validation.sh"
}

teardown() {
    rm -rf "$AWB_ROOT" "$STUB_BIN"
}

# Writes an os-release fixture and points validate_os at it.
_fake_os_release() {
    export AWB_OS_RELEASE="${AWB_ROOT}/os-release"
    printf '%s\n' "$@" > "$AWB_OS_RELEASE"
}

# --- validate_os ----------------------------------------------------------

@test "validate_os: accepts Ubuntu by ID" {
    _fake_os_release 'ID=ubuntu' 'PRETTY_NAME="Ubuntu 24.04 LTS"'
    run validate_os
    [ "$status" -eq 0 ]
}

@test "validate_os: accepts Pop!_OS, which identifies as ID=pop" {
    _fake_os_release 'ID=pop' 'ID_LIKE="ubuntu debian"' 'PRETTY_NAME="Pop!_OS 24.04 LTS"'
    run validate_os
    [ "$status" -eq 0 ]
}

@test "validate_os: accepts a derivative via ID_LIKE rather than ID" {
    _fake_os_release 'ID=elementary' 'ID_LIKE="ubuntu"' 'PRETTY_NAME="elementary OS 7"'
    run validate_os
    [ "$status" -eq 0 ]
}

@test "validate_os: rejects an unsupported distro" {
    _fake_os_release 'ID=fedora' 'ID_LIKE="rhel"' 'PRETTY_NAME="Fedora 40"'
    run validate_os
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unsupported distribution"* ]]
}

@test "validate_os: names the offending distro so the error is actionable" {
    _fake_os_release 'ID=arch' 'PRETTY_NAME="Arch Linux"'
    run validate_os
    [[ "$output" == *"Arch Linux"* ]]
}

@test "validate_os: fails loud when os-release is missing entirely" {
    export AWB_OS_RELEASE="${AWB_ROOT}/definitely-absent"
    run validate_os
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot detect OS"* ]]
}

@test "validate_os: exports the parsed id and pretty name on success" {
    _fake_os_release 'ID=ubuntu' 'PRETTY_NAME="Ubuntu 24.04 LTS"'
    validate_os
    [ "$AWB_OS_ID" = "ubuntu" ]
    [ "$AWB_OS_PRETTY" = "Ubuntu 24.04 LTS" ]
}

# --- validate_arch --------------------------------------------------------

@test "validate_arch: rejects arm64, which v1.0 does not support" {
    cat >"${STUB_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
echo aarch64
EOF
    chmod +x "${STUB_BIN}/uname"
    PATH="${STUB_BIN}:${PATH}" run validate_arch
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unsupported architecture"* ]]
}

@test "validate_arch: accepts x86_64 and exports it" {
    cat >"${STUB_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
echo x86_64
EOF
    chmod +x "${STUB_BIN}/uname"
    PATH="${STUB_BIN}:${PATH}" validate_arch
    [ "$AWB_ARCH" = "x86_64" ]
}

# --- validate_ram ---------------------------------------------------------
# Driven by the threshold rather than by faking /proc/meminfo: passing an
# absurd minimum forces the low-memory branch on any real machine.

@test "validate_ram: sets AWB_LOW_MEMORY=true below the threshold" {
    validate_ram 999999
    [ "$AWB_LOW_MEMORY" = "true" ]
}

@test "validate_ram: sets AWB_LOW_MEMORY=false at or above the threshold" {
    validate_ram 1
    [ "$AWB_LOW_MEMORY" = "false" ]
}

@test "validate_ram: warns but does NOT abort on low memory" {
    # The distinction doctor.sh mirrors as warn-vs-fail: install continues on a
    # small machine with reduced defaults instead of refusing to run.
    run validate_ram 999999
    [ "$status" -eq 0 ]
}

# --- validate_disk_space --------------------------------------------------

@test "validate_disk_space: passes when free space exceeds the minimum" {
    run validate_disk_space 1 "$AWB_ROOT"
    [ "$status" -eq 0 ]
}

@test "validate_disk_space: aborts when free space is short" {
    run validate_disk_space 999999999 "$AWB_ROOT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Insufficient disk space"* ]]
}

@test "validate_disk_space: skips rather than aborts when the path is unreadable" {
    # df fails on a nonexistent path; an undeterminable check must not be
    # treated as a failed one.
    run validate_disk_space 10 "/nonexistent/path/for/test"
    [ "$status" -eq 0 ]
}

@test "validate_disk_space: defaults to \$HOME when no path is given" {
    run validate_disk_space 1
    [ "$status" -eq 0 ]
}

# --- validate_not_root_unless_intended ------------------------------------

# Only the non-root path is covered: EUID is readonly in bash, so the root
# branch cannot be reached without actually running as root, and adding a seam
# to production code to test one log_warn is not worth the surface area.
@test "validate_not_root_unless_intended: silent and non-fatal for a normal user" {
    run validate_not_root_unless_intended
    [ "$status" -eq 0 ]
    [[ "$output" != *"Running as root"* ]]
}

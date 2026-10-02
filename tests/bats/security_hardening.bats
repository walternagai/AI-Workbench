#!/usr/bin/env bats
# Security guards: secrets placeholders, config.local.env permissions, and
# NPU driver signature checking. Hermetic — no network, gpg or sudo needed.

setup() {
    export AWB_ROOT HOME
    AWB_ROOT="$(mktemp -d)"
    HOME="${AWB_ROOT}/home"
    mkdir -p "$HOME"
    source "${BATS_TEST_DIRNAME}/../../lib/colors.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/logger.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/utils.sh"
}

teardown() {
    rm -rf "$AWB_ROOT"
}

# --- tracked config carries no real secrets -----------------------------------

@test "config.env ships change-me placeholders, not real secrets" {
    cfg="${BATS_TEST_DIRNAME}/../../config.env"
    grep -qx 'WEBUI_SECRET_KEY=change-me' "$cfg"
    grep -qx 'POSTGRES_PASSWORD=change-me' "$cfg"
}

# --- services refuse the placeholder --------------------------------------------

@test "_require_real_secret: aborts on the change-me placeholder" {
    source "${BATS_TEST_DIRNAME}/../../services/install.sh"
    run _require_real_secret WEBUI_SECRET_KEY change-me
    [ "$status" -ne 0 ]
    [[ "$output" == *"WEBUI_SECRET_KEY"*"config.local.env"* ]]
}

@test "_require_real_secret: accepts a real value" {
    source "${BATS_TEST_DIRNAME}/../../services/install.sh"
    run _require_real_secret WEBUI_SECRET_KEY a-real-secret
    [ "$status" -eq 0 ]
}

# --- load_local_env ---------------------------------------------------------------

@test "load_local_env: loads a 600 file owned by the user" {
    printf 'AWB_TEST_SECRET=ok\n' > "${AWB_ROOT}/config.local.env"
    chmod 600 "${AWB_ROOT}/config.local.env"
    load_local_env "${AWB_ROOT}/config.local.env"
    [ "$AWB_TEST_SECRET" = "ok" ]
}

@test "load_local_env: a missing file is not an error" {
    run load_local_env "${AWB_ROOT}/absent.env"
    [ "$status" -eq 0 ]
}

@test "load_local_env: refuses a group/world-readable file and does not source it" {
    printf 'AWB_TEST_SECRET=leaked\n' > "${AWB_ROOT}/config.local.env"
    chmod 644 "${AWB_ROOT}/config.local.env"
    run load_local_env "${AWB_ROOT}/config.local.env"
    [ "$status" -ne 0 ]
    [[ "$output" == *"chmod 600"* ]]
    [ -z "${AWB_TEST_SECRET:-}" ]
}

# --- NPU signature verification ----------------------------------------------------

_npu_setup() {
    source "${BATS_TEST_DIRNAME}/../../platforms/intel/npu.sh"
    export AWB_NPU_GPG_FINGERPRINT="AAAA1111"
    mkdir -p "${AWB_ROOT}/bin"
    PATH="${AWB_ROOT}/bin:${PATH}"
    : > "${AWB_ROOT}/drv.deb"
}

# gpg stub: $1 is the VALIDSIG line to print (empty = exit 1 like a bad sig).
_stub_gpg() {
    if [ -n "$1" ]; then
        printf '#!/bin/sh\necho "[GNUPG:] VALIDSIG %s"\n' "$1" > "${AWB_ROOT}/bin/gpg"
    else
        printf '#!/bin/sh\nexit 1\n' > "${AWB_ROOT}/bin/gpg"
    fi
    chmod +x "${AWB_ROOT}/bin/gpg"
}

@test "_npu_verify_debs: passes when signed by the pinned fingerprint" {
    _npu_setup
    : > "${AWB_ROOT}/drv.deb.asc"
    _stub_gpg "AAAA1111 2024-01-01"
    run _npu_verify_debs "${AWB_ROOT}/drv.deb"
    [ "$status" -eq 0 ]
}

@test "_npu_verify_debs: rejects a valid signature from a different key" {
    _npu_setup
    : > "${AWB_ROOT}/drv.deb.asc"
    _stub_gpg "BBBB2222 2024-01-01"
    run _npu_verify_debs "${AWB_ROOT}/drv.deb"
    [ "$status" -ne 0 ]
}

@test "_npu_verify_debs: rejects a failed signature check" {
    _npu_setup
    : > "${AWB_ROOT}/drv.deb.asc"
    _stub_gpg ""
    run _npu_verify_debs "${AWB_ROOT}/drv.deb"
    [ "$status" -ne 0 ]
}

@test "_npu_verify_debs: rejects a .deb with no signature file" {
    _npu_setup
    _stub_gpg "AAAA1111 2024-01-01"
    run _npu_verify_debs "${AWB_ROOT}/drv.deb"
    [ "$status" -ne 0 ]
}

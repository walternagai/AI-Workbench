#!/usr/bin/env bats
# Security guards: secrets placeholders and config.local.env permissions.
# Hermetic — no network, gpg or sudo needed.

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

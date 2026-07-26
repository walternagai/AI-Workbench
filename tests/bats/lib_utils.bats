#!/usr/bin/env bats
# Unit tests for the pure, deterministic helpers in lib/utils.sh — no
# hardware, network, or package manager required. Run with:
#   bats tests/bats/lib_utils.bats

setup() {
    export AWB_ROOT
    AWB_ROOT="$(mktemp -d)"
    source "${BATS_TEST_DIRNAME}/../../lib/colors.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/logger.sh"
    source "${BATS_TEST_DIRNAME}/../../lib/utils.sh"
}

teardown() {
    rm -rf "$AWB_ROOT"
}

# --- has_cmd -----------------------------------------------------------------

@test "has_cmd: true for a binary on PATH" {
    run has_cmd bash
    [ "$status" -eq 0 ]
}

@test "has_cmd: false for a nonexistent binary" {
    run has_cmd definitely-not-a-real-command-xyz
    [ "$status" -ne 0 ]
}

# --- is_true -------------------------------------------------------------------

@test "is_true: accepts true/1/yes case-insensitively" {
    for v in true True TRUE 1 yes Yes YES; do
        run is_true "$v"
        [ "$status" -eq 0 ]
    done
}

@test "is_true: rejects false/0/no/empty/garbage" {
    for v in false False 0 no "" garbage; do
        run is_true "$v"
        [ "$status" -ne 0 ]
    done
}

# --- ensure_dir ----------------------------------------------------------------

@test "ensure_dir: creates a nested directory" {
    target="${AWB_ROOT}/a/b/c"
    run ensure_dir "$target"
    [ "$status" -eq 0 ]
    [ -d "$target" ]
}

@test "ensure_dir: is idempotent on an existing directory" {
    target="${AWB_ROOT}/exists"
    mkdir -p "$target"
    run ensure_dir "$target"
    [ "$status" -eq 0 ]
}

# --- retry -----------------------------------------------------------------------

@test "retry: succeeds immediately when the command succeeds on the first try" {
    run retry 3 0 true
    [ "$status" -eq 0 ]
}

@test "retry: gives up and returns non-zero after n attempts" {
    run retry 3 0 false
    [ "$status" -eq 1 ]
}

@test "retry: succeeds once a flaky command starts succeeding" {
    counter_file="${AWB_ROOT}/counter"
    echo 0 > "$counter_file"
    _flaky() {
        local n
        n=$(<"$counter_file")
        n=$((n + 1))
        echo "$n" > "$counter_file"
        [[ "$n" -ge 3 ]]
    }
    run retry 5 0 _flaky
    [ "$status" -eq 0 ]
    [ "$(cat "$counter_file")" -eq 3 ]
}

# --- json_kv ---------------------------------------------------------------------

@test "json_kv: emits a plain key/value pair" {
    run json_kv name "value"
    [ "$output" = '  "name": "value"' ]
}

@test "json_kv: escapes backslashes and double quotes" {
    run json_kv key 'back\slash and "quote"'
    [ "$output" = '  "key": "back\\slash and \"quote\""' ]
}

@test "json_kv: escapes newlines, tabs and carriage returns" {
    run json_kv key "$(printf 'a\tb\nc\rd')"
    [ "$output" = '  "key": "a\tb\nc\rd"' ]
}

@test "json_kv: strips raw control characters instead of leaving them in the JSON" {
    run json_kv key "$(printf 'a\x01b')"
    [ "$output" = '  "key": "ab"' ]
}

# Regression: the control-character strip was written as tr -d '[\000-...]'.
# tr has no bracket-grouping syntax, so the [] were deleted as literals — and
# lspci names every GPU with brackets, so hardware.json reported the model of
# this machine's iGPU as "Meteor Lake-P Intel Arc Graphics".
@test "json_kv: keeps square brackets, which lspci device names depend on" {
    run json_kv gpu_model 'Meteor Lake-P [Intel Arc Graphics]'
    [ "$output" = '  "gpu_model": "Meteor Lake-P [Intel Arc Graphics]"' ]
}

# --- require_cmd -------------------------------------------------------------

@test "require_cmd: silent for a command that exists" {
    run require_cmd bash "the shell"
    [ "$status" -eq 0 ]
}

@test "require_cmd: fails loud and names both the command and the reason" {
    run require_cmd definitely-not-a-real-binary "needed for the thing"
    [ "$status" -ne 0 ]
    [[ "$output" == *"definitely-not-a-real-binary"* ]]
    [[ "$output" == *"needed for the thing"* ]]
}

# --- safe_source -------------------------------------------------------------

@test "safe_source: sources a file that exists and runs its contents" {
    printf 'AWB_TEST_SOURCED=yes\n' > "${AWB_ROOT}/mod.sh"
    safe_source "${AWB_ROOT}/mod.sh"
    [ "$AWB_TEST_SOURCED" = "yes" ]
}

@test "safe_source: fails loud instead of silently continuing when missing" {
    # The whole point of the helper: a missing module must abort here rather
    # than surface later as an undefined function.
    run safe_source "${AWB_ROOT}/no-such-module.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Required module not found"* ]]
}

# --- load_env ----------------------------------------------------------------

@test "load_env: exports the variables it reads" {
    printf 'AWB_TEST_FLAG=true\nAWB_TEST_NAME=workbench\n' > "${AWB_ROOT}/env"
    load_env "${AWB_ROOT}/env"
    [ "$AWB_TEST_FLAG" = "true" ]
    [ "$AWB_TEST_NAME" = "workbench" ]
}

@test "load_env: marks variables for export, not just assignment" {
    # load_env wraps the source in set -a precisely so child processes (the
    # installer shells out constantly) inherit config.env.
    printf 'AWB_TEST_EXPORTED=yes\n' > "${AWB_ROOT}/env"
    load_env "${AWB_ROOT}/env"
    run bash -c 'printf "%s" "$AWB_TEST_EXPORTED"'
    [ "$output" = "yes" ]
}

@test "load_env: a missing optional file is not an error" {
    run load_env "${AWB_ROOT}/absent.env"
    [ "$status" -eq 0 ]
}

@test "load_env: a missing required file fails loud" {
    run load_env "${AWB_ROOT}/absent.env" true
    [ "$status" -ne 0 ]
    [[ "$output" == *"Required environment file not found"* ]]
}

@test "load_env: later values win, so a re-read overrides an earlier one" {
    printf 'AWB_TEST_V=first\n'  > "${AWB_ROOT}/a.env"
    printf 'AWB_TEST_V=second\n' > "${AWB_ROOT}/b.env"
    load_env "${AWB_ROOT}/a.env"
    load_env "${AWB_ROOT}/b.env"
    [ "$AWB_TEST_V" = "second" ]
}

# --- ensure_prereq_dirs ------------------------------------------------------
# PRINCIPLES.md §2: these are created unconditionally, before any platform or
# runtime branch, because a runtime once assumed a directory that only a
# platform branch had created.

@test "ensure_prereq_dirs: creates every directory the installer assumes exists" {
    export HOME="${AWB_ROOT}/home"
    export AI_HOME="${AWB_ROOT}/home/ai"
    ensure_prereq_dirs
    [ -d "${AWB_ROOT}/logs" ]
    [ -d "${AWB_ROOT}/reports" ]
    [ -d "${AI_HOME}" ]
    [ -d "${AI_HOME}/models" ]
    [ -d "${AI_HOME}/bin" ]
    [ -d "${HOME}/venvs" ]
}

@test "ensure_prereq_dirs: honours AI_HOME instead of hardcoding ~/ai" {
    export HOME="${AWB_ROOT}/home"
    export AI_HOME="${AWB_ROOT}/elsewhere"
    ensure_prereq_dirs
    [ -d "${AWB_ROOT}/elsewhere/models" ]
    [ ! -d "${AWB_ROOT}/home/ai" ]
}

@test "ensure_prereq_dirs: is idempotent" {
    export HOME="${AWB_ROOT}/home"
    export AI_HOME="${AWB_ROOT}/home/ai"
    ensure_prereq_dirs
    run ensure_prereq_dirs
    [ "$status" -eq 0 ]
}

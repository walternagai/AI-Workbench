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

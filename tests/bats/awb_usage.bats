#!/usr/bin/env bats
# Unit tests for _usage() in scripts/awb.
#
# The help text is not written out anywhere: it is the script's own header
# comment, printed back by slicing the file. That slice used a hardcoded line
# range (`sed -n '2,20p'`), and line 20 had stopped being the last comment line
# — so `awb --help` ended every run by printing `set -euo pipefail` as if it
# were a documented command. Nothing else in the repo could catch it: shellcheck
# sees a valid sed call, and no test read the output.
#
# These run the real CLI and assert on what it prints. Run with:
#   bats tests/bats/awb_usage.bats

setup() {
    AWB_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    AWB="${AWB_ROOT}/scripts/awb"
    export AWB_ROOT AWB
}

# --- the regression -------------------------------------------------------

@test "usage does not leak the shell directives below the header comment" {
    run "$AWB" --help
    [ "$status" -eq 0 ]
    [[ "$output" != *"set -euo pipefail"* ]] \
        || { echo "shell code leaked into the help text:"; echo "$output"; return 1; }
}

@test "usage prints only header-comment lines" {
    # Generalises the check above: the slice must stop at the first non-comment
    # line whatever gets added there next, so no line of the output may look
    # like shell. Everything legitimate is either blank, the banner, or an
    # indented "awb ..." entry.
    run "$AWB" --help
    [ "$status" -eq 0 ]
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == "scripts/awb"* || "$line" == "Usage:" || "$line" == "  awb "* ]] \
            || { echo "unexpected line in help output: ${line}"; return 1; }
    done <<<"$output"
}

@test "usage keeps its first and last documented lines" {
    # Guards the other end: a slice that starts or stops early silently drops
    # commands instead of adding junk.
    run "$AWB" --help
    [ "$status" -eq 0 ]
    [[ "${lines[0]}" == "scripts/awb — AI-Workbench CLI entrypoint." ]] \
        || { echo "unexpected first line: ${lines[0]}"; return 1; }
    [[ "${lines[-1]}" == "  awb benchmark <llm|whisper|vision|embeddings> [args...]" ]] \
        || { echo "unexpected last line: ${lines[-1]}"; return 1; }
}

@test "usage strips the comment markers" {
    run "$AWB" --help
    [ "$status" -eq 0 ]
    [[ "$output" != *"#"* ]] || { echo "'#' left in the help text:"; echo "$output"; return 1; }
}

# --- invocation -----------------------------------------------------------

@test "-h, --help, help and no argument all print the same usage" {
    run "$AWB" --help
    [ "$status" -eq 0 ]
    expected="$output"
    for arg in -h help ""; do
        run "$AWB" $arg
        [ "$status" -eq 0 ] || { echo "'awb ${arg}' exited ${status}"; return 1; }
        [ "$output" = "$expected" ] || { echo "'awb ${arg}' printed different usage"; return 1; }
    done
}

@test "an unknown command prints the usage and exits non-zero" {
    run "$AWB" definitely-not-a-command
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown command: definitely-not-a-command"* ]]
    [[ "$output" == *"awb benchmark"* ]] || { echo "usage missing from the error path"; return 1; }
    [[ "$output" != *"set -euo pipefail"* ]]
}

@test "usage works when awb is invoked through a symlink" {
    # awb is meant to be linked into a PATH dir, so BASH_SOURCE[0] is the
    # symlink; reading the header from it must still resolve to the real file.
    ln -s "$AWB" "${BATS_TEST_TMPDIR}/awb"
    run "${BATS_TEST_TMPDIR}/awb" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"awb benchmark"* ]] || { echo "usage empty via symlink:"; echo "$output"; return 1; }
}

# --- agreement with the dispatcher ----------------------------------------

@test "every documented command has a case branch" {
    # The header is hand-maintained prose; this is what keeps it honest.
    run "$AWB" --help
    [ "$status" -eq 0 ]
    while IFS= read -r cmd; do
        grep -qE "^[[:space:]]*${cmd}[|)]" "$AWB" \
            || { echo "'awb ${cmd}' is documented but has no case branch"; return 1; }
    done < <(awk '/^  awb /{ print $2 }' <<<"$output" | sort -u)
}

@test "every case branch is documented" {
    while IFS= read -r cmd; do
        grep -qE "^  awb ${cmd}( |$)" <<<"$(cd "$AWB_ROOT" && "$AWB" --help)" \
            || { echo "'awb ${cmd}' is dispatched but undocumented"; return 1; }
    done < <(awk 'match($0, /^    [a-z_.]+\)/) { print substr($0, 5, RLENGTH - 5) }' "$AWB")
}

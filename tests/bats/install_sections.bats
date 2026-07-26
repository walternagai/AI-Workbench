#!/usr/bin/env bats
# Structural tests for install.sh's section wiring.
#
# A section is four things that must agree: a RUN_* default, an arm in --only,
# an arm in --skip, and a call in main(). They are four separate hand-edited
# lists, so adding a section is exactly the kind of change that half-lands —
# a --skip arm with no --only arm, or a RUN_* that _disable_all_sections
# forgets and so leaks into every --only run. install.sh cannot be sourced to
# check this (it parses argv and runs main at import), so these read the file.
# Run with:
#   bats tests/bats/install_sections.bats

setup() {
    AWB_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    export AWB_ROOT
    INSTALL_SH="${AWB_ROOT}/install.sh"
    export INSTALL_SH
}

# Every RUN_* variable declared as a top-level default.
_run_vars() {
    grep -oE '^RUN_[A-Z_]+=' "$INSTALL_SH" | tr -d '='
}

# Section names accepted by --only / --skip. Both case blocks list the same
# names, so parsing the --skip one is enough to enumerate them.
_section_names() {
    sed -n '/--skip)/,/esac/p' "$INSTALL_SH" | grep -oE '^ +[a-z]+\)' | tr -d ' )'
}

@test "every RUN_* variable is cleared by _disable_all_sections" {
    # A RUN_* missing here stays true under --only, so `--only cli` would also
    # run whatever was forgotten.
    body="$(sed -n '/^_disable_all_sections()/,/^}/p' "$INSTALL_SH")"
    for var in $(_run_vars); do
        [[ "$body" == *"${var}=false"* ]] || { echo "_disable_all_sections does not clear ${var}"; return 1; }
    done
}

@test "every RUN_* variable is actually consulted in main()" {
    body="$(sed -n '/^main()/,/^}/p' "$INSTALL_SH")"
    for var in $(_run_vars); do
        [[ "$body" == *"\$${var}\""* ]] || { echo "main() never checks ${var}"; return 1; }
    done
}

@test "every section name is accepted by both --only and --skip" {
    only_block="$(sed -n '/--only)/,/esac/p' "$INSTALL_SH")"
    for name in $(_section_names); do
        [[ "$only_block" == *"${name})"* ]] || { echo "--only rejects section '${name}' that --skip accepts"; return 1; }
    done
}

@test "every section name maps to a section_* function that exists" {
    for name in $(_section_names); do
        # system -> section_system_update is the one intentional rename.
        fn="section_${name}"
        [[ "$name" == "system" ]] && fn="section_system_update"
        grep -qE "^${fn}\(\)" "$INSTALL_SH" || { echo "section '${name}' has no ${fn}() definition"; return 1; }
    done
}

@test "every section_* function is reachable through --only" {
    # Catches the reverse omission: a section added to main() but never wired
    # into the flag parser, so it cannot be re-run selectively (PRINCIPLES §3).
    names="$(_section_names)"
    while read -r fn; do
        # prereqs runs unconditionally and is deliberately not a flag.
        [[ "$fn" == "section_prereqs" ]] && continue
        short="${fn#section_}"
        [[ "$short" == "system_update" ]] && short="system"
        [[ " $(echo "$names" | tr '\n' ' ') " == *" ${short} "* ]] \
            || { echo "${fn}() is not reachable via --only ${short}"; return 1; }
    done < <(grep -oE '^section_[a-z_]+\(\)' "$INSTALL_SH" | tr -d '()')
}

@test "the --help text lists every section the parser accepts" {
    help="$(sed -n '/^_print_help()/,/^}/p' "$INSTALL_SH")"
    for name in $(_section_names); do
        [[ "$help" == *"$name"* ]] || { echo "--help does not mention section '${name}'"; return 1; }
    done
}

@test "--only rejects an unknown section instead of silently doing nothing" {
    run bash "$INSTALL_SH" --only definitely-not-a-section
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown section"* ]]
}

@test "--skip rejects an unknown section" {
    run bash "$INSTALL_SH" --skip definitely-not-a-section
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown section"* ]]
}

@test "an unknown argument is rejected rather than ignored" {
    run bash "$INSTALL_SH" --definitely-not-a-flag
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown argument"* ]]
}

@test "--help exits cleanly without running an install" {
    run bash "$INSTALL_SH" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: install.sh"* ]]
    [[ "$output" != *"Validating system"* ]]
}

@test "the Makefile's install-* targets name real sections" {
    names=" $(_section_names | tr '\n' ' ') "
    while read -r target; do
        [[ "$names" == *" ${target} "* ]] || { echo "Makefile target install-${target} is not a section"; return 1; }
    done < <(grep -oE '^install-[a-z]+:' "${AWB_ROOT}/Makefile" | sed 's/^install-//; s/://')
}

@test "every entrypoint loads config.local.env after config.env" {
    # Order matters: loaded first, the tracked defaults would clobber the
    # overrides. Loaded not at all, a secret set there is silently ignored and
    # the service starts with 'change-me'.
    for f in install.sh doctor.sh update.sh; do
        base="$(grep -n 'load_env .*config\.env' "${AWB_ROOT}/${f}" | head -1 | cut -d: -f1)"
        local_="$(grep -n 'load_env .*config\.local\.env' "${AWB_ROOT}/${f}" | head -1 | cut -d: -f1)"
        [ -n "$local_" ] || { echo "${f} never loads config.local.env"; return 1; }
        [ "$local_" -gt "$base" ] || { echo "${f} loads config.local.env at line ${local_}, before config.env at ${base}"; return 1; }
    done
}

@test "config.local.env is gitignored so secrets cannot be committed" {
    run git -C "$AWB_ROOT" check-ignore config.local.env
    [ "$status" -eq 0 ] || { echo "config.local.env is NOT gitignored — a secret written there would be committed"; return 1; }
}

@test "the tracked config.env holds no real secret" {
    # Placeholders are fine and expected; anything that looks like a generated
    # key in a public, committed file is not.
    while read -r line; do
        value="${line#*=}"
        case "$value" in
            change-me|awb|"") continue ;;
        esac
        [[ ! "$value" =~ ^[0-9a-fA-F]{32,}$ ]] \
            || { echo "config.env line looks like a real secret: ${line%%=*}=<redacted>"; return 1; }
    done < <(grep -iE '^[A-Z_]*(SECRET|PASSWORD|TOKEN|KEY)[A-Z_]*=' "${AWB_ROOT}/config.env")
}
